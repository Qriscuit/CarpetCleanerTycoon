"""Serve a local ad review with byte ranges, so browser video seeking works."""
from __future__ import annotations

import argparse
from datetime import timezone
from email.utils import parsedate_to_datetime
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re


class ReviewHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def end_headers(self):
        # Every refresh must revalidate artwork/video that was just regenerated.
        self.send_header("Cache-Control", "no-cache, max-age=0")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def send_head(self):
        self._range = None
        path = Path(self.translate_path(self.path)).resolve()
        root = Path(self.directory).resolve()
        if not path.is_relative_to(root):
            self.send_error(403, "Path is outside the review directory")
            return None
        if path.is_dir():
            return super().send_head()
        try:
            source = path.open("rb")
        except OSError:
            self.send_error(404, "File not found")
            return None
        try:
            info = os.fstat(source.fileno())
            size = info.st_size
            etag = f'"{info.st_mtime_ns:x}-{size:x}"'
            requested = self.headers.get("Range")
            if_range = self.headers.get("If-Range")
            if requested and if_range:
                matches = if_range == etag
                if not matches and not if_range.startswith(('"', 'W/')):
                    try:
                        stamp = parsedate_to_datetime(if_range)
                        if stamp.tzinfo is None:
                            stamp = stamp.replace(tzinfo=timezone.utc)
                        matches = int(info.st_mtime) <= int(stamp.timestamp())
                    except (ValueError, TypeError, OverflowError):
                        pass
                if not matches:
                    requested = None
            start, end = 0, size - 1
            if requested and requested.startswith("bytes="):
                match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested.strip())
                valid = bool(match and any(match.groups()) and size)
                if valid:
                    first, last = match.groups()
                    if first:
                        start = int(first)
                        end = min(int(last), size - 1) if last else size - 1
                        valid = start < size and start <= end
                    else:
                        suffix = int(last)
                        valid = suffix > 0
                        start = max(0, size - suffix)
                if not valid:
                    source.close()
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.send_header("Content-Length", "0")
                    self.send_header("Accept-Ranges", "bytes")
                    self.end_headers()
                    return None
                self._range = (start, end)
            self.send_response(206 if self._range else 200)
            self.send_header("Content-Type", self.guess_type(str(path)))
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Last-Modified", self.date_time_string(info.st_mtime))
            self.send_header("ETag", etag)
            self.send_header("Accept-Ranges", "bytes")
            if self._range:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                source.seek(start)
            self.end_headers()
            return source
        except Exception:
            source.close()
            raise

    def copyfile(self, source, outputfile):
        remaining = self._range[1] - self._range[0] + 1 if self._range else None
        try:
            while remaining is None or remaining > 0:
                block = source.read(65536 if remaining is None else min(65536, remaining))
                if not block:
                    break
                outputfile.write(block)
                if remaining is not None:
                    remaining -= len(block)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # Browsers cancel an old byte range when a user seeks again.
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8768)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    directory = args.directory.resolve()
    if not directory.is_dir():
        parser.error("--directory must be an existing directory")
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    handler = partial(ReviewHandler, directory=str(directory))
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Review ready: http://127.0.0.1:{args.port}/Review.html", flush=True)
        print(f"Directory: {directory}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
