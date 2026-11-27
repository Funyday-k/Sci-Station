"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const STATIC_ROOT = path.join(__dirname, "..", "..", "web", "static");

function parseBindings(spec) {
  return spec
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const match = part.match(/^(\w+)\s+as\s+(\w+)$/);
      return match ? [match[1], match[2]] : [part, part];
    });
}

function loadESMInContext(relativePath, sandbox, cache = new Map()) {
  const ctx = vm.isContext(sandbox) ? sandbox : vm.createContext(sandbox);
  const absPath = path.resolve(STATIC_ROOT, relativePath);
  if (cache.has(absPath)) return cache.get(absPath);

  const source = fs.readFileSync(absPath, "utf8");
  const dir = path.dirname(absPath);
  const importedModules = [];
  const exportedNames = new Set();

  let transformed = source.replace(
    /^import\s+\{([\s\S]*?)\}\s+from\s+["']([^"']+)["'];?\s*$/gm,
    (_, bindingsText, specifier) => {
      const depAbs = path.resolve(dir, specifier);
      const depRel = path.relative(STATIC_ROOT, depAbs);
      const depExports = loadESMInContext(depRel, ctx, cache);
      const idx = importedModules.length;
      importedModules.push(depExports);
      const pairs = parseBindings(bindingsText);
      return pairs
        .map(([orig, local]) => `const ${local} = __esmDeps[${idx}][${JSON.stringify(orig)}];`)
        .join("\n");
    },
  );

  transformed = transformed.replace(
    /^export\s+(async\s+)?function\s+(\w+)/gm,
    (_, asyncKw, name) => {
      exportedNames.add(name);
      return `${asyncKw || ""}function ${name}`;
    },
  );

  transformed = transformed.replace(
    /^export\s+(const|let|var)\s+(\w+)/gm,
    (_, decl, name) => {
      exportedNames.add(name);
      return `${decl} ${name}`;
    },
  );

  const exportLines = [...exportedNames]
    .map((name) => `  __esmExports[${JSON.stringify(name)}] = ${name};`)
    .join("\n");

  const wrapped = `(function(__esmDeps, __esmExports) {\n"use strict";\n${transformed}\n${exportLines}\n})`;
  const exportsObj = {};
  cache.set(absPath, exportsObj);

  const runner = vm.runInContext(wrapped, ctx, { filename: absPath });
  runner(importedModules, exportsObj);
  return exportsObj;
}

function runStaticScriptInContext(relativePath, sandbox) {
  if (relativePath.startsWith("modules/")) {
    return loadESMInContext(relativePath, sandbox);
  }
  const absPath = path.resolve(STATIC_ROOT, relativePath);
  return vm.runInContext(fs.readFileSync(absPath, "utf8"), sandbox, { filename: absPath });
}

module.exports = {
  loadESMInContext,
  runStaticScriptInContext,
};
