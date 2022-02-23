const fs = require("./dir-helpers.js");
const fsPromises = require("fs").promises;

const { runElmReview } = require("./compile-elm.js");
const { restoreColorSafe } = require("./error-formatter");
const path = require("path");
const spawnCallback = require("cross-spawn").spawn;
const codegen = require("./codegen.js");
const terser = require("terser");
const os = require("os");
const { Worker, SHARE_ENV } = require("worker_threads");
const { ensureDirSync } = require("./file-helpers.js");
const { generateClientFolder } = require("./codegen.js");
const which = require("which");
const { build } = require("vite");
const preRenderHtml = require("./pre-render-html.js");

let pool = [];
let pagesReady;
let pages = new Promise((resolve, reject) => {
  pagesReady = resolve;
});
let buildError = false;

const DIR_PATH = process.cwd();
const OUTPUT_FILE_NAME = "elm.js";

process.on("unhandledRejection", (error) => {
  console.log(error);
  process.exitCode = 1;
});

const ELM_FILE_PATH = path.join(
  DIR_PATH,
  "./elm-stuff/elm-pages",
  OUTPUT_FILE_NAME
);

async function ensureRequiredDirs() {
  ensureDirSync(`dist`);
  ensureDirSync(path.join(process.cwd(), ".elm-pages", "http-response-cache"));
}

async function ensureRequiredExecutables() {
  try {
    await which("lamdera");
  } catch (error) {
    throw "I couldn't find elm on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
  try {
    await which("elm-optimize-level-2");
  } catch (error) {
    throw "I couldn't find elm-optimize-level-2 on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
  try {
    await which("elm-review");
  } catch (error) {
    throw "I couldn't find elm-review on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
}

async function run(options) {
  try {
    await ensureRequiredDirs();
    await ensureRequiredExecutables();
    // since init/update are never called in pre-renders, and DataSource.Http is called using pure NodeJS HTTP fetching
    // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)

    const generateCode = codegen.generate(options.base);

    await generateCode;
    await fsPromises.writeFile(
      "elm-stuff/elm-pages/index.html",
      preRenderHtml.templateHtml()
    );

    const viteConfig = await import(
      path.join(process.cwd(), "elm-pages.config.mjs")
    )
      .then(async (elmPagesConfig) => {
        return elmPagesConfig.default.vite || {};
      })
      .catch((error) => {
        console.trace("Config loading error", error);
        process.exit(1);
      });

    await build({
      configFile: false,
      root: process.cwd(),
      base: options.base,

      build: {
        outDir: "dist",
        rollupOptions: {
          ssr: false,
          input: "elm-stuff/elm-pages/index.html",
        },
      },
      ...viteConfig,
    });
    const compileClientDone = compileElm(options);
    await compileClientDone;
    await fsPromises.copyFile(
      "dist/elm-stuff/elm-pages/index.html",
      "dist/template.html"
    );

    XMLHttpRequest = {};
    const compileCli = compileCliApp(options);
    try {
      await compileCli;
    } catch (cliError) {
      console.error(cliError);
      process.exit(1);
    }
    const cliDone = runCli(options);
    await cliDone;

  } catch (error) {
    buildError = true;
    try {
      const reviewOutput = JSON.parse(await runElmReview());
      const isParsingError = reviewOutput.errors.some((reviewError) => {
        return reviewError.errors.some((item) => item.rule === "ParsingError");
      });
      if (isParsingError) {
        console.error(error);
      } else {
        console.error(restoreColorSafe(reviewOutput));
      }
      process.exitCode = 1;
    } catch (noElmReviewErrors) {
      console.error(error);
    } finally {
    }
  }
}

/**
 * @param {string} basePath
 */
function initWorker(basePath) {
  return new Promise((resolve, reject) => {
    let newWorker = {
      worker: new Worker(path.join(__dirname, "./render-worker.js"), {
        env: SHARE_ENV,
        workerData: { basePath },
      }),
    };
    newWorker.worker.once("online", () => {
      newWorker.worker.on("message", (message) => {
        if (message.tag === "all-paths") {
          pagesReady(JSON.parse(message.data));
        } else if (message.tag === "error") {
          process.exitCode = 1;
          console.error(restoreColorSafe(message.data));
          buildNextPage(newWorker);
        } else if (message.tag === "done") {
          buildNextPage(newWorker);
        } else {
          throw `Unhandled tag ${message.tag}`;
        }
      });
      newWorker.worker.on("error", (error) => {
        console.error("Unhandled worker exception", error);
        process.exitCode = 1;
        buildNextPage(newWorker);
      });
      resolve(newWorker);
    });
  });
}

/**
 */
function prepareStaticPathsNew(thread) {
  thread.worker.postMessage({
    mode: "build",
    tag: "render",
    pathname: "/all-paths.json",
  });
}

async function buildNextPage(thread) {
  let nextPage = (await pages).pop();
  if (nextPage) {
    thread.worker.postMessage({
      mode: "build",
      tag: "render",
      pathname: nextPage,
    });
  } else {
    thread.worker.terminate();
  }
}

async function runCli(options) {
  const cpuCount = os.cpus().length;
  console.log("Threads: ", cpuCount);

  const getPathsWorker = initWorker(options.base);
  getPathsWorker.then(prepareStaticPathsNew);
  const threadsToCreate = Math.max(1, cpuCount - 1);
  pool.push(getPathsWorker);
  for (let index = 0; index < threadsToCreate - 1; index++) {
    pool.push(initWorker(options.base));
  }
  pool.forEach((threadPromise) => {
    threadPromise.then(buildNextPage);
  });
}

async function compileElm(options) {
  ensureDirSync("dist");
  const fullOutputPath = path.join(process.cwd(), `./dist/elm.js`);
  await generateClientFolder(options.base);
  await spawnElmMake(
    options,
    ".elm-pages/Main.elm",
    fullOutputPath,
    path.join(process.cwd(), "./elm-stuff/elm-pages/client")
  );

  if (!options.debug) {
    await runTerser(fullOutputPath);
  }
}

function elmOptimizeLevel2(outputPath, cwd) {
  return new Promise((resolve, reject) => {
    const optimizedOutputPath = outputPath + ".opt";
    const subprocess = spawnCallback(
      `elm-optimize-level-2`,
      [outputPath, "--output", optimizedOutputPath],
      {
        // ignore stdout
        // stdio: ["inherit", "ignore", "inherit"],

        cwd: cwd,
      }
    );
    let commandOutput = "";

    subprocess.stderr.on("data", function (data) {
      commandOutput += data;
    });

    subprocess.on("close", async (code) => {
      if (
        code === 0 &&
        commandOutput === "" &&
        (await fs.fileExists(optimizedOutputPath))
      ) {
        await fs.copyFile(optimizedOutputPath, outputPath);
        resolve();
      } else {
        if (!buildError) {
          buildError = true;
          process.exitCode = 1;
          reject(commandOutput);
        } else {
          // avoid unhandled error printing duplicate message, let process.exit in top loop take over
        }
      }
    });
  });
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string | undefined} cwd
 */
async function spawnElmMake(options, elmEntrypointPath, outputPath, cwd) {
  await runElmMake(options, elmEntrypointPath, outputPath, cwd);
  if (!options.debug) {
    await elmOptimizeLevel2(outputPath, cwd);
  }
  await fsPromises.writeFile(
    outputPath,
    (
      await fsPromises.readFile(outputPath, "utf-8")
    ).replace(
      /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_FORM_TO_STRING.\)/g,
      "let appendSubmitter = (myFormData, event) => { event.submitter && event.submitter.name && event.submitter.name.length > 0 ? myFormData.append(event.submitter.name, event.submitter.value) : myFormData;  return myFormData }; return " +
        (options.debug
          ? "_Json_wrap([...(appendSubmitter(new FormData(_Json_unwrap(event).target), _Json_unwrap(event)))])"
          : "[...(new FormData(event.target))")
    )
  );
}

function runElmMake(options, elmEntrypointPath, outputPath, cwd) {
  return new Promise(async (resolve, reject) => {
    const subprocess = spawnCallback(
      `lamdera`,
      [
        "make",
        elmEntrypointPath,
        "--output",
        outputPath,
        ...(options.debug ? ["--debug"] : ["--optimize"]),
        "--report",
        "json",
      ],
      {
        // ignore stdout
        // stdio: ["inherit", "ignore", "inherit"],

        cwd: cwd,
      }
    );
    if (await fs.fileExists(outputPath)) {
      await fsPromises.unlink(outputPath, {
        force: true /* ignore errors if file doesn't exist */,
      });
    }
    let commandOutput = "";

    subprocess.stderr.on("data", function (data) {
      commandOutput += data;
    });
    subprocess.on("error", function () {
      reject(commandOutput);
    });

    subprocess.on("close", async (code) => {
      if (
        code == 0 &&
        (await fs.fileExists(outputPath)) &&
        commandOutput === ""
      ) {
        resolve();
      } else {
        if (!buildError) {
          buildError = true;
          try {
            reject(restoreColorSafe(commandOutput));
          } catch (error) {
            reject(commandOutput);
          }
        } else {
          // avoid unhandled error printing duplicate message, let process.exit in top loop take over
        }
      }
    });
  });
}

/**
 * @param {string} filePath
 */
async function runTerser(filePath) {
  console.log("Running terser");
  const minifiedElm = await terser.minify(
    (await fsPromises.readFile(filePath)).toString(),
    {
      ecma: 5,

      module: true,
      compress: {
        pure_funcs: [
          "F2",
          "F3",
          "F4",
          "F5",
          "F6",
          "F7",
          "F8",
          "F9",
          "A2",
          "A3",
          "A4",
          "A5",
          "A6",
          "A7",
          "A8",
          "A9",
        ],
        pure_getters: true,
        keep_fargs: false,
        unsafe_comps: true,
        unsafe: true,
        passes: 2,
      },
      mangle: true,
    }
  );
  if (minifiedElm.code) {
    await fsPromises.writeFile(filePath, minifiedElm.code);
  } else {
    throw "Error running terser.";
  }
}

async function compileCliApp(options) {
  await spawnElmMake(
    options,
    path.join(process.cwd(), "elm-stuff/elm-pages/.elm-pages/Main.elm"),
    path.join(process.cwd(), "elm-stuff/elm-pages/elm.js"),
    path.join(process.cwd(), "elm-stuff/elm-pages")
  );

  const elmFileContent = await fsPromises.readFile(ELM_FILE_PATH, "utf-8");
  // Source: https://github.com/elm-explorations/test/blob/d5eb84809de0f8bbf50303efd26889092c800609/src/Elm/Kernel/HtmlAsJson.js
  const forceThunksSource = ` _HtmlAsJson_toJson(x)
}

              var virtualDomKernelConstants =
  {
    nodeTypeTagger: 4,
    nodeTypeThunk: 5,
    kids: "e",
    refs: "l",
    thunk: "m",
    node: "k",
    value: "a"
  }

function forceThunks(vNode) {
  if (typeof vNode !== "undefined" && vNode.$ === "#2") {
    // This is a tuple (the kids : List (String, Html) field of a Keyed node); recurse into the right side of the tuple
    vNode.b = forceThunks(vNode.b);
  }
  if (typeof vNode !== 'undefined' && vNode.$ === virtualDomKernelConstants.nodeTypeThunk && !vNode[virtualDomKernelConstants.node]) {
    // This is a lazy node; evaluate it
    var args = vNode[virtualDomKernelConstants.thunk];
    vNode[virtualDomKernelConstants.node] = vNode[virtualDomKernelConstants.thunk].apply(args);
    // And then recurse into the evaluated node
    vNode[virtualDomKernelConstants.node] = forceThunks(vNode[virtualDomKernelConstants.node]);
  }
  if (typeof vNode !== 'undefined' && vNode.$ === virtualDomKernelConstants.nodeTypeTagger) {
    // This is an Html.map; recurse into the node it is wrapping
    vNode[virtualDomKernelConstants.node] = forceThunks(vNode[virtualDomKernelConstants.node]);
  }
  if (typeof vNode !== 'undefined' && typeof vNode[virtualDomKernelConstants.kids] !== 'undefined') {
    // This is something with children (either a node with kids : List Html, or keyed with kids : List (String, Html));
    // recurse into the children
    vNode[virtualDomKernelConstants.kids] = vNode[virtualDomKernelConstants.kids].map(forceThunks);
  }
  return vNode;
}

function _HtmlAsJson_toJson(html) {
`;

  await fsPromises.writeFile(
    ELM_FILE_PATH,
    elmFileContent
      .replace(
        /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
        "return " +
          (options.debug
            ? `${forceThunksSource}
  return _Json_wrap(forceThunks(html));
`
            : `${forceThunksSource}
return forceThunks(html);
`)
      )
      .replace(
        "return ports ? { ports: ports } : {};",
        `const die = function() {
        managers = null
        model = null
        stepper = null
        ports = null
      }

      return ports ? { ports: ports, die: die } : { die: die };`
      )
  );
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; body: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

/** @typedef {     { body: string; head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */

/**
 * @param {Arg} fromElm
 * @param {string} contentJsonString
 * @returns {string}
 */

module.exports = { run };
