// replication-materials 1.3.0
// Builds the static site from the markdown record: node build-site.mjs --root . --out _site
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadProject } from "./lib/project.mjs";
import { renderSite } from "./lib/pages.mjs";

function parseArgs(argv) {
  const opts = { root: ".", out: "_site" };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root" && argv[i + 1] !== undefined) opts.root = argv[++i];
    else if (argv[i] === "--out" && argv[i + 1] !== undefined) {
      opts.out = argv[++i];
      if (opts.out.trim() === "") throw new Error("--out needs a folder name.");
    }
    else throw new Error(`unknown or incomplete argument "${argv[i]}". Use --root <dir> and --out <dir>.`);
  }
  return opts;
}

function gitSha(root) {
  if (process.env.GIT_SHA) return process.env.GIT_SHA;
  try {
    return execFileSync("git", ["rev-parse", "--short", "HEAD"], {
      cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim() || "local";
  } catch {
    return "local";
  }
}

function outIsUsable(out) {
  if (!existsSync(out) || readdirSync(out).length === 0) return true;
  const index = join(out, "index.html");
  // A site of any version of the skill can be replaced (an update changes the version).
  return existsSync(index)
    && /<meta name="generator" content="replication-materials \d+\.\d+\.\d+">/.test(readFileSync(index, "utf8"));
}

export async function main(argv) {
  try {
    const args = parseArgs(argv);
    const { root } = args;
    const out = resolve(args.out);
    const model = loadProject(root, { gitSha: gitSha(root) });
    if (!outIsUsable(out)) {
      process.stderr.write(`replication-materials: ${args.out} is not empty and is not a previous site.\n`);
      return 1;
    }
    const site = renderSite(model);
    // Empty the folder, not remove it: Windows can hold a lock on the folder itself.
    if (existsSync(out)) for (const f of readdirSync(out)) rmSync(join(out, f), { recursive: true, force: true });
    for (const [path, html] of site) {
      const target = join(out, path);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, html);
    }
    // Extra pages are copied as they are, byte for byte.
    const extra = model.config.pages;
    for (const page of extra) {
      const target = join(out, page.path);
      mkdirSync(dirname(target), { recursive: true });
      copyFileSync(join(root, page.file), target);
    }
    const copied = extra.length ? ` and ${extra.length} extra page${extra.length === 1 ? "" : "s"}` : "";
    process.stdout.write(`Wrote ${site.size} pages${copied} to ${args.out}.\n`);
    return 0;
  } catch (e) {
    process.stderr.write(`replication-materials: ${e.message}\n`);
    return 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
