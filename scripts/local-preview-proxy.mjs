import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const mimeTypes = { ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".map": "application/json; charset=utf-8", ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon", ".woff": "font/woff", ".woff2": "font/woff2" };

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "client");
const targetPort = Number(process.env.LOCAL_RUNTIME_PORT || 3000);
const port = Number(process.env.LOCAL_PROXY_PORT || 3002);

const server = http.createServer((req, res) => {
  if (req.url?.startsWith("/assets/")) {
    const relative = decodeURIComponent(req.url.slice(1));
    const file = path.resolve(root, relative);
    if (file.startsWith(root + path.sep) && fs.existsSync(file) && fs.statSync(file).isFile()) {
      res.writeHead(200, { "Content-Type": mimeTypes[path.extname(file).toLowerCase()] || "application/octet-stream" });
      fs.createReadStream(file).pipe(res);
      return;
    }
  }

  const proxy = http.request({ hostname: "127.0.0.1", port: targetPort, path: req.url, method: req.method, headers: req.headers }, (upstream) => {
    res.writeHead(upstream.statusCode ?? 502, upstream.headers);
    upstream.pipe(res);
  });
  proxy.on("error", (error) => {
    res.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
    res.end(`Local runtime indisponível: ${error.message}`);
  });
  req.pipe(proxy);
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Local Central proxy running at http://localhost:${port}`);
});
