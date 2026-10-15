import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const port = Number(process.env.PORT || 3000);
const upstream = "http://127.0.0.1:3001";
const clientRoot = path.resolve("dist/client");

const proxy = (req, res) => {
  const target = new URL(req.url || "/", upstream);
  const request = http.request(target, { method: req.method, headers: req.headers }, response => {
    res.writeHead(response.statusCode || 502, response.headers);
    response.pipe(res);
  });
  request.on("error", error => { res.writeHead(502, { "content-type": "text/plain" }); res.end(error.message); });
  req.pipe(request);
};

http.createServer((req, res) => {
  const pathname = new URL(req.url || "/", "http://localhost").pathname;
  if (pathname.startsWith("/assets/") || pathname.startsWith("/platforms/") || pathname.endsWith(".png") || pathname.endsWith(".svg")) {
    const file = path.resolve(clientRoot, `.${pathname}`);
    if (file.startsWith(clientRoot) && fs.existsSync(file)) {
      const type = pathname.endsWith(".js") ? "application/javascript; charset=utf-8" : pathname.endsWith(".css") ? "text/css; charset=utf-8" : pathname.endsWith(".svg") ? "image/svg+xml" : "image/png";
      res.writeHead(200, { "content-type": type, "cache-control": "no-cache" });
      fs.createReadStream(file).pipe(res);
      return;
    }
  }
  proxy(req, res);
}).listen(port, "127.0.0.1", () => console.log(`Local preview proxy at http://localhost:${port}`));
