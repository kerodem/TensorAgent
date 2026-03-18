import fs from "fs";
import path from "path";

export default function handler(req, res) {
  const filePath = path.join(process.cwd(), "install.sh");
  const script = fs.readFileSync(filePath, "utf8");

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.status(200).send(script);
}
