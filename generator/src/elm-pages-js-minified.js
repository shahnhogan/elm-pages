module.exports = `let prefetchedPages=[window.location.pathname],initialLocationHash=document.location.hash.replace(/^#/,"");function loadContentAndInitializeApp(){let a=window.location.pathname.replace(/(\w)$/,"$1/");a.endsWith("/")||(a+="/");const b=Elm.TemplateModulesBeta.init({flags:{secrets:null,baseUrl:document.baseURI,isPrerendering:!1,isDevServer:!1,isElmDebugMode:!1,contentJson:JSON.parse(document.getElementById("__ELM_PAGES_DATA__").innerHTML),userFlags:userInit.flags()}});return b.ports.toJsPort.subscribe(()=>{loadNamedAnchor()}),b}function loadNamedAnchor(){if(""!==initialLocationHash){const a=document.querySelector(\`[name=\${initialLocationHash}]\`);a&&a.scrollIntoView()}}function prefetchIfNeeded(a){if(a.host===window.location.host&&!prefetchedPages.includes(a.pathname)){prefetchedPages.push(a.pathname),console.log("Preloading...",a.pathname);const b=document.createElement("link");b.setAttribute("as","fetch"),b.setAttribute("rel","prefetch"),b.setAttribute("href",origin+a.pathname+"/content.json"),document.head.appendChild(b)}}const appPromise=new Promise(function(a){document.addEventListener("DOMContentLoaded",()=>{a(loadContentAndInitializeApp())})});userInit.load(appPromise),"function"==typeof connect&&connect(function(a){appPromise.then(b=>{b.ports.fromJsPort.send({contentJson:a})})});const trigger_prefetch=b=>{const c=find_anchor(b.target);c&&c.href&&c.hasAttribute("elm-pages:prefetch")&&prefetchIfNeeded(c)};let mousemove_timeout;const handle_mousemove=a=>{clearTimeout(mousemove_timeout),mousemove_timeout=setTimeout(()=>{trigger_prefetch(a)},20)};addEventListener("touchstart",trigger_prefetch),addEventListener("mousemove",handle_mousemove);function find_anchor(a){for(;a&&"A"!==a.nodeName.toUpperCase();)a=a.parentNode;return a}`;
