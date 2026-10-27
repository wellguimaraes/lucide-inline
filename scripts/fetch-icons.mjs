// Downloads the latest lucide-static package and writes Resources/icons.json
// as [{ name, tags, svg }]. Run: node scripts/fetch-icons.mjs [version]
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const version = process.argv[2] ?? "latest";
const tmp = mkdtempSync(join(tmpdir(), "lucide-"));

try {
  const tarball = execFileSync("npm", ["pack", `lucide-static@${version}`, "--silent"], { cwd: tmp })
    .toString().trim().split("\n").pop();
  execFileSync("tar", ["xzf", tarball], { cwd: tmp });

  const pkg = join(tmp, "package");
  const tags = JSON.parse(readFileSync(join(pkg, "tags.json"), "utf8"));
  const { version: resolved } = JSON.parse(readFileSync(join(pkg, "package.json"), "utf8"));

  const icons = readdirSync(join(pkg, "icons"))
    .filter((f) => f.endsWith(".svg"))
    .sort()
    .map((file) => {
      const name = file.slice(0, -4);
      const svg = readFileSync(join(pkg, "icons", file), "utf8")
        .replace(/<!--[\s\S]*?-->/g, "")
        .trim();
      return { name, tags: tags[name] ?? [], svg };
    });

  writeFileSync(join(root, "Resources", "icons.json"), JSON.stringify({ version: resolved, icons }));
  console.log(`Wrote ${icons.length} icons from lucide-static@${resolved}`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
