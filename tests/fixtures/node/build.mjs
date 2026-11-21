// Écrit la version du package.json dans dist/version.txt, comme un bundler l'embarquerait.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

const { version } = JSON.parse(readFileSync("package.json", "utf8"));
mkdirSync("dist", { recursive: true });
writeFileSync("dist/version.txt", `${version}\n`);
console.log(`fixture ${version}`);
