const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { chromium } = require("playwright");

const HERE = __dirname;
const MOD = path.resolve(HERE, "..");
const OUT = path.join(MOD, "files", "generated");
const CFG = path.join(HERE, "config.json");

const sleep = ms => new Promise(r => setTimeout(r, ms));
const readCfg = () => JSON.parse(fs.readFileSync(CFG, "utf8"));

function isAllowedHttpUrl(value) {
  try {
    const url = new URL(String(value));
    return url.protocol === "http:" || url.protocol === "https:";
  } catch (_) {
    return false;
  }
}

function openUrlInDefaultBrowser(url) {
  if (!isAllowedHttpUrl(url)) return false;

  const cp = require("child_process");

  try {
    let child;

    if (process.platform === "win32") {
      child = cp.spawn(
        "rundll32.exe",
        ["url.dll,FileProtocolHandler", url],
        { detached: true, stdio: "ignore", windowsHide: true }
      );
    } else if (process.platform === "darwin") {
      child = cp.spawn(
        "open",
        [url],
        { detached: true, stdio: "ignore" }
      );
    } else {
      child = cp.spawn(
        "xdg-open",
        [url],
        { detached: true, stdio: "ignore" }
      );
    }

    child.unref();
    console.log("[Birthday Link] Opened:", url);
    return true;
  } catch (e) {
    console.error("[Birthday Link] Open failed:", e.message);
    return false;
  }
}

function manifestAllowsCardUrl(cardId, url) {
  const file = path.join(OUT, "manifest.txt");
  if (!fs.existsSync(file)) return false;

  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);

  for (const line of lines) {
    if (!line.trim()) continue;

    const parts = line.split("|");
    if (parts.length < 9) continue;
    if (parts[1] !== cardId) continue;

    const links = decodeManifestLinks(parts[8] || "");
    return links.includes(url);
  }

  return false;
}



function startBirthdayLinkFileWatcher() {
  const requestFile = path.join(OUT, "open_link_request.txt");
  let lastRequest = "";

  console.log("[Birthday Link] Watching runtime link requests.");

  return setInterval(() => {
    try {
      if (!fs.existsSync(requestFile)) return;

      const raw = fs.readFileSync(requestFile, "utf8").trim();
      if (!raw || raw === lastRequest) return;

      const lines = raw.split(/\r?\n/);
      const cardId = String(lines[0] || "").trim();
      const url = String(lines[1] || "").trim();

      console.log("[Birthday Link] Request:", cardId, url);

      if (
        cardId &&
        isAllowedHttpUrl(url) &&
        manifestAllowsCardUrl(cardId, url)
      ) {
        openUrlInDefaultBrowser(url);
      } else {
        console.error("[Birthday Link] Rejected request.");
      }

      lastRequest = raw;
    } catch (e) {
      console.error("[Birthday Link] Request watcher error:", e.message);
    }
  }, 250);
}


function normalizeText(text) {
  return (text || "").replace(/\s+/g, " ").trim();
}

function area(box) {
  return Math.max(0, box.width) * Math.max(0, box.height);
}

function containsBox(outer, inner, tolerance = 4) {
  return (
    inner.x >= outer.x - tolerance &&
    inner.y >= outer.y - tolerance &&
    inner.x + inner.width <= outer.x + outer.width + tolerance &&
    inner.y + inner.height <= outer.y + outer.height + tolerance
  );
}

function textRelated(a, b) {
  const ta = normalizeText(a).toLowerCase();
  const tb = normalizeText(b).toLowerCase();

  if (!ta || !tb) return false;
  if (ta === tb) return true;

  const shorter = ta.length <= tb.length ? ta : tb;
  const longer = ta.length > tb.length ? ta : tb;

  return shorter.length >= 12 && longer.includes(shorter);
}

function candidateQuality(c) {
  return (c.imgCount || 0) * 1000000 + area(c.box);
}

function dedupeCandidates(list) {
  const rejected = [];
  const kept = [];
  let exactDuplicates = 0;
  let nearDuplicates = 0;

  const normalized = list.map(candidate => {
    const value = normalizeMatchText(candidate.text || "");
    return {
      candidate,
      value,
      length: value.length
    };
  });

  const relation = (a, b) => {
    if (!a || !b) return null;
    if (a === b) return "exact";

    const shorter = a.length <= b.length ? a : b;
    const longer = a.length > b.length ? a : b;

    if (shorter.length < 12) return null;
    if (!longer.includes(shorter)) return null;

    const delta = longer.length - shorter.length;
    const ratio = shorter.length / Math.max(1, longer.length);

    if (delta <= 90 && ratio >= 0.82) return "near";
    return null;
  };

  const groups = [];

  for (const item of normalized) {
    let target = null;
    let targetRelation = null;

    for (const group of groups) {
      for (const member of group.members) {
        const rel = relation(item.value, member.value);
        if (!rel) continue;
        target = group;
        targetRelation = rel;
        break;
      }
      if (target) break;
    }

    if (!target) {
      groups.push({
        members: [item],
        relations: []
      });
      continue;
    }

    target.members.push(item);
    target.relations.push(targetRelation);
  }

  const fullCardScore = item => {
    const candidate = item.candidate;
    const textLength = item.length;
    const boxArea = Math.max(1, area(candidate.box));
    const width = Math.max(1, candidate.box.width || 0);
    const height = Math.max(1, candidate.box.height || 0);
    const aspectPenalty = width > 0 && height / width > 4.5 ? 200000 : 0;

    return (
      (candidate.imgCount || 0) * 1000000 +
      Math.min(boxArea, 900000) +
      Math.min(textLength, 4000) * 100 -
      aspectPenalty
    );
  };

  for (const group of groups) {
    if (group.members.length === 1) {
      kept.push(group.members[0].candidate);
      continue;
    }

    const sorted = [...group.members].sort(
      (a, b) => fullCardScore(b) - fullCardScore(a)
    );

    const winner = sorted[0];
    kept.push(winner.candidate);

    for (const item of sorted.slice(1)) {
      const rel = relation(item.value, winner.value) || "content";
      if (rel === "exact") exactDuplicates++;
      else nearDuplicates++;

      const shorterLength = Math.min(item.value.length, winner.value.length);
      const longerLength = Math.max(item.value.length, winner.value.length);
      const ratio = longerLength > 0 ? shorterLength / longerLength : 0;

      rejected.push({
        index: item.candidate.index,
        winnerIndex: winner.candidate.index,
        reason: rel === "exact"
          ? "exact card content duplicate"
          : "same card content with short wrapper text",
        ratio,
        delta: longerLength - shorterLength,
        text: normalizeText(item.candidate.text),
        winnerText: normalizeText(winner.candidate.text)
      });
    }
  }

  kept.sort((a, b) => a.index - b.index);

  console.log(
    `Content identity dedupe: raw=${list.length}, unique=${kept.length}, ` +
    `exactDuplicates=${exactDuplicates}, nearDuplicates=${nearDuplicates}`
  );

  return { kept, rejected };
}

async function hideNoise(page, selectors) {
  for (const s of selectors || []) {
    try {
      await page.locator(s).evaluateAll(es =>
        es.forEach(e => e.style.setProperty("display", "none", "important"))
      );
    } catch (_) {}
  }
}

async function plausible(page, selector, c) {
  const loc = page.locator(selector);
  const count = Math.min(await loc.count(), 300);
  const out = [];

  for (let i = 0; i < count; i++) {
    const el = loc.nth(i);

    try {
      if (!(await el.isVisible())) continue;

      const b = await el.boundingBox();
      if (!b) continue;

      if (b.width < c.minimumCardWidth || b.height < c.minimumCardHeight) continue;

      const configuredMaxWidth = Number(c.maximumCardWidth) || 1000;
      const configuredMaxHeight = Number(c.maximumCardHeight) || 1000;
      const tallCardMaxWidth = Math.min(520, configuredMaxWidth);
      const isTallCard =
        b.width <= tallCardMaxWidth &&
        b.height > configuredMaxHeight &&
        b.height <= 1800;

      if (b.width > configuredMaxWidth) continue;
      if (b.height > configuredMaxHeight && !isTallCard) continue;

      const rawText = await el.innerText().catch(() => "");
      const text = normalizeText(rawText);
      const textLines = String(rawText)
        .split(/\r?\n/)
        .map(x => normalizeText(x))
        .filter(Boolean);
      const author = textLines.length ? textLines[0] : "Birthday Spirit";
      const imgCount = await el.locator("img").count().catch(() => 0);
      const mediaUrls = await el.locator("img,video,source").evaluateAll(nodes =>
        nodes
          .flatMap(node => [
            node.currentSrc || "",
            node.src || "",
            node.getAttribute("src") || "",
            node.getAttribute("poster") || ""
          ])
          .filter(Boolean)
      ).catch(() => []);

      const links = await el.locator("a[href]").evaluateAll(nodes =>
        nodes
          .map(node => node.href || node.getAttribute("href") || "")
          .filter(Boolean)
      ).catch(() => []);

      const ancestorContext = await el.evaluate(node => {
        const texts = [];
        const media = [];
        const seenText = new Set();
        const seenMedia = new Set();
        let current = node.parentElement;

        for (let depth = 0; current && depth < 12; depth++, current = current.parentElement) {
          if (current === document.body || current === document.documentElement) break;

          const rect = current.getBoundingClientRect();
          if (
            rect.width < 120 || rect.height < 60 ||
            rect.width > 1000 || rect.height > 1800
          ) continue;

          const t = String(current.innerText || "").replace(/\s+/g, " ").trim();
          if (t && t.length <= 12000 && !seenText.has(t)) {
            seenText.add(t);
            texts.push(t);
          }

          for (const mediaNode of current.querySelectorAll("img,video,source")) {
            const values = [
              mediaNode.currentSrc || "",
              mediaNode.src || "",
              mediaNode.getAttribute("src") || "",
              mediaNode.getAttribute("poster") || ""
            ];

            for (const value of values) {
              if (!value || seenMedia.has(value)) continue;
              seenMedia.add(value);
              media.push(value);
            }
          }
        }

        return { texts, media };
      }).catch(() => ({ texts: [], media: [] }));

      if (text.length < 2 && imgCount === 0) continue;

      out.push({
        index: i,
        box: b,
        text,
        rawText,
        author,
        links,
        imgCount,
        mediaUrls,
        ancestorTexts: ancestorContext.texts,
        ancestorMediaUrls: ancestorContext.media
      });
    } catch (_) {}
  }

  return out;
}

async function dedupeDomContainedCandidates(page, selector, raw) {
  if (!raw.length) return { kept: [], rejected: [] };

  const indices = raw.map(x => x.index);
  const relations = await page.locator(selector).evaluateAll((nodes, candidateIndices) => {
    const result = [];

    for (const outerIndex of candidateIndices) {
      const outer = nodes[outerIndex];
      if (!outer) continue;

      const descendants = [];

      for (const innerIndex of candidateIndices) {
        if (innerIndex === outerIndex) continue;
        const inner = nodes[innerIndex];
        if (!inner) continue;
        if (outer.contains(inner)) descendants.push(innerIndex);
      }

      if (descendants.length) {
        result.push({ outerIndex, descendants });
      }
    }

    return result;
  }, indices).catch(() => []);

  const byIndex = new Map(raw.map(x => [x.index, x]));
  const parentFor = new Map();

  for (const relation of relations) {
    const outer = byIndex.get(relation.outerIndex);
    if (!outer) continue;

    for (const innerIndex of relation.descendants) {
      const inner = byIndex.get(innerIndex);
      if (!inner) continue;

      const currentParentIndex = parentFor.get(innerIndex);
      if (currentParentIndex === undefined) {
        parentFor.set(innerIndex, relation.outerIndex);
        continue;
      }

      const currentParent = byIndex.get(currentParentIndex);
      if (!currentParent || area(outer.box) < area(currentParent.box)) {
        parentFor.set(innerIndex, relation.outerIndex);
      }
    }
  }

  const rejectedIndices = new Set(parentFor.keys());
  const kept = raw.filter(x => !rejectedIndices.has(x.index));
  const rejected = [];

  for (const [innerIndex, outerIndex] of parentFor.entries()) {
    const inner = byIndex.get(innerIndex);
    const outer = byIndex.get(outerIndex);
    if (!inner || !outer) continue;

    rejected.push({
      index: innerIndex,
      winnerIndex: outerIndex,
      reason: "DOM descendant of card candidate",
      ratio: 0,
      delta: 0,
      text: normalizeText(inner.text),
      winnerText: normalizeText(outer.text)
    });
  }

  kept.sort((a, b) => a.index - b.index);
  rejected.sort((a, b) => a.index - b.index);

  console.log(
    `DOM containment dedupe: raw=${raw.length}, unique=${kept.length}, descendants=${rejected.length}`
  );

  return { kept, rejected };
}

async function inspectSelector(page, selector, c) {
  const raw = await plausible(page, selector, c);

  let result;

  if (c.dedupeNestedCards === false) {
    result = { kept: raw, rejected: [] };
  } else {
    const domResult = await dedupeDomContainedCandidates(page, selector, raw);
    result = domResult.rejected.length
      ? domResult
      : dedupeCandidates(raw);
  }

  return {
    selector,
    raw,
    list: result.kept,
    rejected: result.rejected
  };
}




function normalizeScalar(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "";
}

function firstField(obj, keys) {
  if (!obj || typeof obj !== "object") return "";

  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(obj, key)) {
      const v = normalizeScalar(obj[key]);
      if (v) return v;
    }
  }

  return "";
}

function looksLikePostObject(obj) {
  if (!obj || Array.isArray(obj) || typeof obj !== "object") return false;

  const author = firstField(obj, [
    "author","authorName","username","userName","name","displayName",
    "sender","senderName","from","signer","signerName"
  ]);

  const message = firstField(obj, [
    "message","text","content","body","comment","description","wish",
    "greeting","note","cardText","messageText"
  ]);

  const media = firstField(obj, [
    "image","imageUrl","imageURL","gif","gifUrl","media","mediaUrl",
    "photo","photoUrl","video","videoUrl","attachment","attachmentUrl"
  ]);

  return Boolean(message || (author && media));
}

function postFromObject(obj, pathHint = "") {
  const author = firstField(obj, [
    "author","authorName","username","userName","name","displayName",
    "sender","senderName","from","signer","signerName"
  ]);

  const message = firstField(obj, [
    "message","text","content","body","comment","description","wish",
    "greeting","note","cardText","messageText"
  ]);

  const media = firstField(obj, [
    "image","imageUrl","imageURL","gif","gifUrl","media","mediaUrl",
    "photo","photoUrl","video","videoUrl","attachment","attachmentUrl"
  ]);

  const id = firstField(obj, [
    "id","_id","uuid","messageId","postId","cardId","signatureId",
    "entryId","recoId"
  ]);

  return {
    id,
    author,
    message,
    media,
    pathHint
  };
}

function findPostArrays(value, path = "$", out = [], seen = new Set()) {
  if (!value || typeof value !== "object") return out;
  if (seen.has(value)) return out;
  seen.add(value);

  if (Array.isArray(value)) {
    const postLike = value.filter(looksLikePostObject);

    if (postLike.length >= 2) {
      out.push({
        path,
        totalLength: value.length,
        postLikeCount: postLike.length,
        posts: postLike.map((x, i) => postFromObject(x, `${path}[${i}]`))
      });
    }

    for (let i = 0; i < Math.min(value.length, 250); i++) {
      findPostArrays(value[i], `${path}[${i}]`, out, seen);
    }

    return out;
  }

  for (const [key, child] of Object.entries(value)) {
    if (child && typeof child === "object") {
      findPostArrays(child, `${path}.${key}`, out, seen);
    }
  }

  return out;
}

function chooseBestPostArray(arrays) {
  if (!arrays.length) return null;

  const scored = arrays.map(x => {
    const ratio = x.totalLength
      ? x.postLikeCount / x.totalLength
      : 0;

    const pathBonus =
      /(message|post|card|signature|signer|entry|wish|greeting|board)/i.test(x.path)
        ? 50
        : 0;

    return {
      ...x,
      score:
        x.postLikeCount * 100 +
        ratio * 50 +
        pathBonus
    };
  });

  scored.sort((a, b) => b.score - a.score);
  return scored[0];
}

function normalizeMatchText(text) {
  return normalizeText(text)
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function postFingerprint(post) {
  return normalizeMatchText(
    `${post.author || ""} ${post.message || ""}`
  );
}

function uniquePosts(posts) {
  const out = [];
  const seen = new Set();

  for (const post of posts || []) {
    const key =
      post.id ||
      postFingerprint(post) ||
      `${post.pathHint}`;

    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(post);
  }

  return out;
}

async function installBoardDataCapture(page) {
  const captured = [];

  const handler = async (response) => {
    try {
      const headers = await response.allHeaders();
      const ct = String(headers["content-type"] || "").toLowerCase();

      if (!ct.includes("json")) return;

      const text = await response.text();
      if (!text || text.length > 8_000_000) return;

      let data;
      try {
        data = JSON.parse(text);
      } catch (_) {
        return;
      }

      captured.push({
        url: response.url(),
        data
      });
    } catch (_) {}
  };

  page.on("response", handler);

  return {
    captured,
    dispose: () => {
      try {
        page.off("response", handler);
      } catch (_) {}
    }
  };
}

async function collectEmbeddedBoardData(page) {
  return await page.evaluate(() => {
    const values = [];

    if (window.__NEXT_DATA__) {
      values.push({
        source: "window.__NEXT_DATA__",
        data: window.__NEXT_DATA__
      });
    }

    if (window.__NUXT__) {
      values.push({
        source: "window.__NUXT__",
        data: window.__NUXT__
      });
    }

    const scripts = [...document.querySelectorAll("script")];

    for (let i = 0; i < scripts.length; i++) {
      const script = scripts[i];
      const type = String(script.type || "").toLowerCase();
      const text = String(script.textContent || "").trim();

      if (!text || text.length > 8_000_000) continue;

      const mightBeJson =
        type.includes("json") ||
        script.id === "__NEXT_DATA__" ||
        (text.startsWith("{") && text.endsWith("}")) ||
        (text.startsWith("[") && text.endsWith("]"));

      if (!mightBeJson) continue;

      try {
        const parsed = JSON.parse(text);
        values.push({
          source: `script#${script.id || i}`,
          data: parsed
        });
      } catch (_) {}
    }

    return values;
  });
}

async function discoverBoardPosts(page, networkCaptured) {
  const candidates = [];

  for (const item of networkCaptured || []) {
    const arrays = findPostArrays(item.data, `network:${item.url}`);

    for (const array of arrays) {
      candidates.push({
        ...array,
        source: item.url
      });
    }
  }

  const embedded = await collectEmbeddedBoardData(page);

  for (const item of embedded) {
    const arrays = findPostArrays(item.data, `embedded:${item.source}`);

    for (const array of arrays) {
      candidates.push({
        ...array,
        source: item.source
      });
    }
  }

  const best = chooseBestPostArray(candidates);

  if (!best) {
    return {
      posts: [],
      candidates: [],
      best: null
    };
  }

  return {
    posts: uniquePosts(best.posts),
    candidates,
    best
  };
}

function compareDataPostsToDom(posts, domCandidates) {
  const mediaKey = value => {
    const raw = String(value || "").trim().toLowerCase();
    if (!raw) return "";
    try {
      const u = new URL(raw);
      return decodeURIComponent(u.pathname).replace(/\/+$/,"");
    } catch (_) {
      return raw.split(/[?#]/)[0];
    }
  };

  const mediaName = value => {
    const key = mediaKey(value);
    if (!key) return "";
    const parts = key.split("/");
    return parts[parts.length - 1] || key;
  };

  const messageProbes = value => {
    const message = normalizeMatchText(value);
    if (!message) return [];

    const sizes = message.length >= 300 ? 80 : 100;
    const maxStart = Math.max(0, message.length - sizes);
    const starts = [
      0,
      Math.floor(maxStart * 0.5),
      maxStart
    ];

    const probes = [];
    const seen = new Set();

    for (const start of starts) {
      const probe = message.slice(start, start + sizes).trim();
      if (probe.length < 12 || seen.has(probe)) continue;
      seen.add(probe);
      probes.push(probe);
    }

    return probes;
  };

  const tokenOverlap = (a, b) => {
    if (!a || !b) return 0;

    const tokensA = new Set(a.split(" ").filter(x => x.length >= 4));
    const tokensB = new Set(b.split(" ").filter(x => x.length >= 4));

    if (!tokensA.size || !tokensB.size) return 0;

    let common = 0;
    for (const token of tokensA) {
      if (tokensB.has(token)) common++;
    }

    return common / Math.min(tokensA.size, tokensB.size);
  };

  const dom = (domCandidates || []).map((x, idx) => ({
    idx,
    text: normalizeMatchText(x.text),
    texts: [x.text, ...(x.ancestorTexts || [])]
      .map(normalizeMatchText)
      .filter(Boolean),
    media: [...(x.mediaUrls || []), ...(x.ancestorMediaUrls || [])]
      .map(mediaKey)
      .filter(Boolean),
    raw: x
  }));

  const rows = [];

  for (let i = 0; i < posts.length; i++) {
    const post = posts[i];
    const fp = postFingerprint(post);
    const author = normalizeMatchText(post.author || "");
    const message = normalizeMatchText(post.message || "");
    const probes = messageProbes(message);
    const postMedia = mediaKey(post.media || "");

    let best = null;
    let bestScore = 0;

    for (const candidate of dom) {
      if (!candidate.texts.length && !candidate.media.length) continue;

      let score = 0;

      for (const candidateText of candidate.texts) {
        let textScore = 0;

        if (fp && candidateText === fp) {
          textScore = 1000;
        } else if (
          fp &&
          (candidateText.includes(fp) || fp.includes(candidateText))
        ) {
          const shorter = Math.min(candidateText.length, fp.length);
          const longer = Math.max(candidateText.length, fp.length);
          textScore = 700 + (shorter / Math.max(1, longer)) * 200;
        } else {
          if (author && candidateText.includes(author)) {
            textScore += 250;
          }

          if (message) {
            let matchedProbes = 0;
            for (const probe of probes) {
              if (candidateText.includes(probe)) matchedProbes++;
            }

            if (matchedProbes > 0) {
              textScore += 500 + Math.min(200, (matchedProbes - 1) * 100);
            } else if (message.length >= 160) {
              const overlap = tokenOverlap(message, candidateText);
              if (overlap >= 0.45) {
                textScore += 350 + Math.min(150, Math.round((overlap - 0.45) * 500));
              }
            }
          }
        }

        if (textScore > score) score = textScore;
      }

      if (postMedia && candidate.media.length) {
        const postName = mediaName(postMedia);
        for (const candidateMedia of candidate.media) {
          const candidateName = mediaName(candidateMedia);
          if (
            candidateMedia === postMedia ||
            candidateMedia.includes(postMedia) ||
            postMedia.includes(candidateMedia) ||
            (postName && candidateName && postName === candidateName)
          ) {
            score += 700;
            break;
          }
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    rows.push({
      dataIndex: i + 1,
      post,
      matchedDomIndex: best && bestScore >= 300
        ? best.idx + 1
        : null,
      score: Math.round(bestScore)
    });
  }

  const bestByDom = new Map();

  for (const row of rows) {
    if (row.matchedDomIndex === null || row.score < 300) continue;
    const existing = bestByDom.get(row.matchedDomIndex);
    if (!existing || row.score > existing.score) {
      if (existing) existing.matchedDomIndex = null;
      bestByDom.set(row.matchedDomIndex, row);
    } else {
      row.matchedDomIndex = null;
    }
  }

  const reliable = rows
    .filter(row => row.matchedDomIndex !== null && row.score >= 300)
    .sort((a, b) => a.dataIndex - b.dataIndex);

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (row.matchedDomIndex !== null) continue;

    let before = null;
    let after = null;

    for (const candidate of reliable) {
      if (candidate.dataIndex < row.dataIndex) before = candidate;
      if (candidate.dataIndex > row.dataIndex) {
        after = candidate;
        break;
      }
    }

    if (!before || !after) continue;

    const dataGap = after.dataIndex - before.dataIndex;
    const domGap = after.matchedDomIndex - before.matchedDomIndex;

    if (dataGap !== domGap || dataGap <= 1) continue;

    const offset = row.dataIndex - before.dataIndex;
    const inferredDomIndex = before.matchedDomIndex + offset;

    if (inferredDomIndex <= 0 || inferredDomIndex > dom.length) continue;

    const alreadyUsed = rows.some(
      other =>
        other !== row &&
        other.matchedDomIndex === inferredDomIndex &&
        other.score >= 300
    );

    if (alreadyUsed) continue;

    row.matchedDomIndex = inferredDomIndex;
    row.score = 299;
  }

  return rows;
}

async function enterLegacyBoardIfNeeded(page, c) {
  const label = /view board/i;

  const candidates = [
    page.getByRole("link", { name: label }).first(),
    page.getByRole("button", { name: label }).first(),
    page.getByText("View Board", { exact: true }).first()
  ];

  let control = null;

  for (const candidate of candidates) {
    try {
      if (await candidate.isVisible({ timeout: 700 })) {
        control = candidate;
        break;
      }
    } catch (_) {}
  }

  if (!control) {
    return false;
  }

  console.log("Legacy Recocards landing page detected: opening View Board...");

  let href = null;

  try {
    href = await control.getAttribute("href");
  } catch (_) {}

  if (href) {
    const target = new URL(href, page.url()).href;

    await page.goto(target, {
      waitUntil: "domcontentloaded",
      timeout: 45000
    });
  } else {
    const beforeUrl = page.url();

    await control.click({ timeout: 10000 });

    try {
      await page.waitForLoadState("domcontentloaded", {
        timeout: 5000
      });
    } catch (_) {}

    if (page.url() === beforeUrl) {
      await sleep(500);
    }
  }

  const waitAfterClick =
    Math.max(500, Number(c.waitAfterLegacyBoardClickMs) || 3500);

  await sleep(waitAfterClick);

  console.log("Legacy board opened:", page.url());
  return true;
}


async function fullyLoadBoardByScrolling(page, c) {
  const maxPasses = Math.max(8, Number(c.legacyScrollMaxPasses) || 50);
  const pause = Math.max(120, Number(c.legacyScrollPauseMs) || 350);

  let stablePasses = 0;
  let lastSignature = "";

  for (let pass = 1; pass <= maxPasses; pass++) {
    await page.evaluate(() => window.scrollTo(0, 0));
    await sleep(Math.min(300, pause));

    let y = 0;
    let stepCount = 0;

    while (stepCount < 200) {
      const state = await page.evaluate(() => {
        const body = document.body;
        const doc = document.documentElement;
        return {
          height: Math.max(
            body ? body.scrollHeight : 0,
            doc ? doc.scrollHeight : 0
          ),
          viewport: Math.max(300, window.innerHeight || 0),
          y: window.scrollY || 0
        };
      });

      const maxY = Math.max(0, state.height - state.viewport);
      if (y >= maxY) break;

      const step = Math.max(240, Math.floor(state.viewport * 0.72));
      y = Math.min(maxY, y + step);

      await page.evaluate(target => window.scrollTo(0, target), y);
      await sleep(Math.max(120, Math.min(250, Math.round(pause * 0.6))));
      stepCount++;
    }

    await page.evaluate(() => {
      const body = document.body;
      const doc = document.documentElement;
      window.scrollTo(0, Math.max(
        body ? body.scrollHeight : 0,
        doc ? doc.scrollHeight : 0
      ));
    });

    await sleep(pause);

    const labels = [
      /load more/i,
      /show more/i,
      /view more/i,
      /more messages/i,
      /more cards/i,
      /next/i
    ];

    for (const label of labels) {
      const controls = [
        page.getByRole("button", { name: label }),
        page.getByRole("link", { name: label })
      ];

      for (const loc of controls) {
        const n = Math.min(await loc.count().catch(() => 0), 10);
        for (let i = 0; i < n; i++) {
          const el = loc.nth(i);
          try {
            if (await el.isVisible()) {
              await el.click({ timeout: 1500 });
              await sleep(pause);
            }
          } catch (_) {}
        }
      }
    }

    const metrics = await page.evaluate(() => {
      const body = document.body;
      const doc = document.documentElement;

      const scrollers = [];

      for (const el of document.querySelectorAll("div,main,section")) {
        const style = getComputedStyle(el);
        const canScroll =
          /(auto|scroll)/.test(style.overflowY) &&
          el.scrollHeight > el.clientHeight + 20;

        if (canScroll) {
          scrollers.push({
            h: el.scrollHeight,
            c: el.clientHeight,
            top: el.scrollTop
          });
        }
      }

      return {
        docHeight: Math.max(
          body ? body.scrollHeight : 0,
          doc ? doc.scrollHeight : 0
        ),
        scrollers,
        cardish:
          document.querySelectorAll("[class*='card' i]").length,
        articles: document.querySelectorAll("article").length,
        items: document.querySelectorAll("li").length
      };
    });

    const signature = JSON.stringify(metrics);

    if (signature === lastSignature) {
      stablePasses++;
    } else {
      stablePasses = 0;
    }

    lastSignature = signature;

    console.log(
      `Board load sweep ${pass}: steps=${stepCount}, cardish=${metrics.cardish}, ` +
      `scrollContainers=${metrics.scrollers.length}, docHeight=${metrics.docHeight}`
    );

    if (pass >= 3 && stablePasses >= 2) break;
  }

  await sleep(Math.max(500, Number(c.legacyScrollFinalWaitMs) || 1500));

  await page.evaluate(() => window.scrollTo(0, 0));
  await sleep(300);
}


async function legacyBroadDetector(page, c) {
  const taggedCount = await page.evaluate((cfg) => {
    const minW = Math.max(240, Number(cfg.minimumCardWidth) || 140);
    const maxW = Math.min(520, Number(cfg.maximumCardWidth) || 1000);
    const minH = 90;
    const maxH = 1800;

    const norm = s => (s || "").replace(/\s+/g, " ").trim();

    const visible = el => {
      const cs = getComputedStyle(el);
      if (cs.display === "none" || cs.visibility === "hidden") return false;
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    };

    const nodes = [];

    for (const el of document.querySelectorAll("div,article,section,li")) {
      if (!visible(el)) continue;
      const r = el.getBoundingClientRect();

      if (
        r.width < minW || r.width > maxW ||
        r.height < minH || r.height > maxH
      ) continue;

      const text = norm(el.innerText);
      const media = el.querySelectorAll("img,video,canvas").length;

      if (text.length < 8 && media === 0) continue;

      nodes.push({
        el,
        x:r.x, y:r.y, w:r.width, h:r.height,
        area:r.width*r.height,
        text,
        media
      });
    }

    const contains = (a,b) =>
      b.x >= a.x-3 && b.y >= a.y-3 &&
      b.x+b.w <= a.x+a.w+3 &&
      b.y+b.h <= a.y+a.h+3;

    nodes.sort((a,b) => b.area-a.area);

    const kept = [];

    for (const n of nodes) {
      let nestedDuplicate = false;

      for (const k of kept) {
        if (!contains(k,n)) continue;

        const nt = n.text.toLowerCase();
        const kt = k.text.toLowerCase();

        const related =
          nt === kt ||
          (nt.length >= 10 && kt.includes(nt)) ||
          (kt.length >= 10 && nt.includes(kt));

        if (related) {
          nestedDuplicate = true;
          break;
        }
      }

      if (!nestedDuplicate) kept.push(n);
    }

    const widths = kept.map(x => x.w);
    const buckets = new Map();

    for (const w of widths) {
      const key = Math.round(w/32)*32;
      buckets.set(key, (buckets.get(key)||0)+1);
    }

    let dominant = null, dominantCount = 0;
    for (const [k,v] of buckets) {
      if (v > dominantCount) {
        dominant = Number(k);
        dominantCount = v;
      }
    }

    let final = kept;
    if (dominant !== null && dominantCount >= 10) {
      final = kept.filter(x => Math.abs(x.w-dominant) <= 90);
    }

    final.sort((a,b) => {
      if (Math.abs(a.y-b.y) > 8) return a.y-b.y;
      return a.x-b.x;
    });

    document.querySelectorAll("[data-recocards-legacy-card]").forEach(el =>
      el.removeAttribute("data-recocards-legacy-card")
    );

    final.forEach((x,i) =>
      x.el.setAttribute("data-recocards-legacy-card", String(i+1))
    );

    return final.length;
  }, c);

  if (!taggedCount) return null;

  const result = await inspectSelector(
    page,
    "[data-recocards-legacy-card]",
    c
  );

  result.genericReport =
    `legacy broad detector tagged=${taggedCount}, accepted=${result.list.length}`;

  return result;
}

async function genericCardFallback(page, c) {
  const result = await page.evaluate((cfg) => {
    const minW = Number(cfg.minimumCardWidth) || 140;
    const minH = Number(cfg.minimumCardHeight) || 80;
    const maxW = Number(cfg.maximumCardWidth) || 1000;
    const maxH = Number(cfg.maximumCardHeight) || 1000;

    const normalize = s => (s || "").replace(/\s+/g, " ").trim();

    const visible = el => {
      const style = getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    };

    const all = [...document.querySelectorAll("div, section, li, article, main > *")];
    const candidates = [];

    for (const el of all) {
      if (!visible(el)) continue;

      const r = el.getBoundingClientRect();
      const tallCardMaxWidth = Math.min(520, maxW);
      const isTallCard =
        r.width <= tallCardMaxWidth &&
        r.height > maxH &&
        r.height <= 1800;

      if (r.width < minW || r.height < minH || r.width > maxW) continue;
      if (r.height > maxH && !isTallCard) continue;

      const text = normalize(el.innerText);
      const imgs = el.querySelectorAll("img").length;
      const videos = el.querySelectorAll("video").length;
      const canvases = el.querySelectorAll("canvas").length;

      if (text.length < 2 && imgs + videos + canvases === 0) continue;

      let plausibleChildren = 0;
      for (const child of el.children) {
        const cr = child.getBoundingClientRect();
        if (
          cr.width >= minW * 0.75 &&
          cr.height >= minH * 0.75 &&
          cr.width <= maxW &&
          cr.height <= maxH
        ) plausibleChildren++;
      }
      if (plausibleChildren >= 3) continue;

      const cls = typeof el.className === "string"
        ? el.className.trim().split(/\s+/).sort().join(".")
        : "";

      const sig = [
        el.tagName,
        Math.round(r.width / 20) * 20,
        Math.round(r.height / 20) * 20,
        el.children.length,
        imgs > 0 ? 1 : 0,
        videos > 0 ? 1 : 0,
        canvases > 0 ? 1 : 0,
        cls
      ].join("|");

      candidates.push({
        el,
        sig,
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
        area: r.width * r.height,
        text,
        imgCount: imgs + videos + canvases
      });
    }

    const groups = new Map();
    for (const x of candidates) {
      if (!groups.has(x.sig)) groups.set(x.sig, []);
      groups.get(x.sig).push(x);
    }

    let best = null;

    for (const [sig, list] of groups) {
      if (list.length < 2) continue;

      const imageCount = list.filter(x => x.imgCount > 0).length;
      const avgText = list.reduce((a, x) => a + x.text.length, 0) / list.length;

      const score =
        list.length * 100 +
        imageCount * 15 +
        Math.min(avgText, 500) * 0.05;

      if (!best || score > best.score) {
        best = { sig, list, score };
      }
    }

    if (!best) {
      const coarse = new Map();

      for (const x of candidates) {
        const sig = [
          x.el.tagName,
          Math.round(x.width / 40) * 40,
          Math.round(x.height / 40) * 40
        ].join("|");

        if (!coarse.has(sig)) coarse.set(sig, []);
        coarse.get(sig).push(x);
      }

      for (const [sig, list] of coarse) {
        if (list.length < 2) continue;

        const score = list.length * 100 +
          list.filter(x => x.imgCount > 0).length * 10;

        if (!best || score > best.score) {
          best = { sig, list, score };
        }
      }
    }

    if (!best) {
      return {
        selector: null,
        count: 0,
        report: "generic fallback found no repeated candidate group"
      };
    }

    const sorted = [...best.list].sort((a, b) => b.area - a.area);
    const kept = [];

    const contains = (a, b) =>
      b.x >= a.x - 4 &&
      b.y >= a.y - 4 &&
      b.x + b.width <= a.x + a.width + 4 &&
      b.y + b.height <= a.y + a.height + 4;

    for (const candidate of sorted) {
      const duplicate = kept.some(existing => {
        const nested = contains(existing, candidate) || contains(candidate, existing);
        const ta = existing.text.toLowerCase();
        const tb = candidate.text.toLowerCase();
        const textRelated =
          ta === tb ||
          (ta.length >= 12 && tb.includes(ta)) ||
          (tb.length >= 12 && ta.includes(tb));
        return nested && textRelated;
      });

      if (!duplicate) kept.push(candidate);
    }

    kept.sort((a, b) => {
      if (Math.abs(a.y - b.y) > 10) return a.y - b.y;
      return a.x - b.x;
    });

    document.querySelectorAll("[data-recocards-auto-card]").forEach(el =>
      el.removeAttribute("data-recocards-auto-card")
    );

    kept.forEach((x, i) => {
      x.el.setAttribute("data-recocards-auto-card", String(i + 1));
    });

    return {
      selector: "[data-recocards-auto-card]",
      count: kept.length,
      report:
        `generic fallback signature=${best.sig} rawGroup=${best.list.length} accepted=${kept.length}`
    };
  }, c);

  if (!result.selector || result.count === 0) {
    return null;
  }

  const inspected = await inspectSelector(page, result.selector, c);
  inspected.genericReport = result.report;
  return inspected;
}

async function unionCardFallback(page, c) {
  const selectors = (c.autoSelectors || []).filter(Boolean);
  if (!selectors.length) return null;

  const taggedCount = await page.evaluate((selectorList) => {
    document.querySelectorAll("[data-recocards-union-card]").forEach(el =>
      el.removeAttribute("data-recocards-union-card")
    );

    const seen = new Set();
    let index = 0;

    for (const selector of selectorList) {
      let nodes = [];
      try {
        nodes = [...document.querySelectorAll(selector)];
      } catch (_) {
        continue;
      }

      for (const node of nodes) {
        if (seen.has(node)) continue;
        seen.add(node);
        node.setAttribute("data-recocards-union-card", String(index + 1));
        index++;
      }
    }

    return index;
  }, selectors);

  if (!taggedCount) return null;

  const result = await inspectSelector(
    page,
    "[data-recocards-union-card]",
    c
  );

  result.genericReport =
    `union detector tagged=${taggedCount}, accepted=${result.list.length}`;

  return result;
}

async function replyCardDetector(page, c) {
  const taggedCount = await page.evaluate(cfg => {
    const minW = Math.max(180, Number(cfg.minimumCardWidth) || 140);
    const maxW = Math.max(520, Number(cfg.maximumCardWidth) || 1000);
    const minH = Math.max(60, Number(cfg.minimumCardHeight) || 80);
    const maxH = 2600;

    document.querySelectorAll("[data-recocards-reply-card]").forEach(el =>
      el.removeAttribute("data-recocards-reply-card")
    );

    const normalize = value =>
      String(value || "").replace(/\s+/g, " ").trim();

    const candidates = [];

    for (const el of document.querySelectorAll("div,article,section,li")) {
      const style = getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden") continue;

      const rect = el.getBoundingClientRect();
      if (
        rect.width < minW ||
        rect.width > maxW ||
        rect.height < minH ||
        rect.height > maxH
      ) continue;

      const text = normalize(el.innerText);
      if (!text) continue;

      const replyMatches = text.match(/\bReply\b/gi) || [];
      if (replyMatches.length !== 1) continue;

      if (!/\bReply\s+(?:Like|\d+\s+likes?)\s*$/i.test(text)) continue;

      candidates.push({
        el,
        area: rect.width * rect.height,
        text
      });
    }

    candidates.sort((a, b) => a.area - b.area);

    const kept = [];

    for (const candidate of candidates) {
      const containsChosen = kept.some(
        existing =>
          candidate.el !== existing.el &&
          candidate.el.contains(existing.el)
      );

      if (containsChosen) continue;

      kept.push(candidate);
    }

    kept.sort((a, b) => {
      const ar = a.el.getBoundingClientRect();
      const br = b.el.getBoundingClientRect();
      if (Math.abs(ar.y - br.y) > 8) return ar.y - br.y;
      return ar.x - br.x;
    });

    kept.forEach((candidate, index) =>
      candidate.el.setAttribute(
        "data-recocards-reply-card",
        String(index + 1)
      )
    );

    return kept.length;
  }, c);

  if (!taggedCount) return null;

  const result = await inspectSelector(
    page,
    "[data-recocards-reply-card]",
    c
  );

  result.replyReport =
    `reply-card detector tagged=${taggedCount}, accepted=${result.list.length}`;

  return result;
}

async function angularCardComponentFallback(page, c) {
  const groups = await page.evaluate(cfg => {
    const minW = Math.max(80, Number(cfg.minimumCardWidth) || 140);
    const minH = Math.max(40, Number(cfg.minimumCardHeight) || 80);
    const maxW = Math.max(minW, Number(cfg.maximumCardWidth) || 1000);
    const maxH = Math.max(1800, Number(cfg.maximumCardHeight) || 1000);
    const skipPrefixes = ["mat-", "fa-", "ng-", "app-root", "app-header", "app-footer"];
    const map = new Map();

    for (const el of document.querySelectorAll("*")) {
      const tag = String(el.tagName || "").toLowerCase();
      if (!tag.includes("-")) continue;
      if (skipPrefixes.some(prefix => tag === prefix || tag.startsWith(prefix))) continue;

      const rect = el.getBoundingClientRect();
      if (rect.width < minW || rect.height < minH) continue;
      if (rect.width > maxW || rect.height > maxH) continue;

      const style = getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden") continue;

      const text = String(el.innerText || "").replace(/\s+/g, " ").trim();
      const mediaCount = el.querySelectorAll("img,video,canvas").length;
      if (text.length < 2 && mediaCount === 0) continue;

      if (!map.has(tag)) {
        map.set(tag, {
          tag,
          count: 0,
          media: 0,
          textTotal: 0,
          areaTotal: 0,
          uniqueTexts: new Set()
        });
      }

      const group = map.get(tag);
      group.count++;
      group.media += mediaCount > 0 ? 1 : 0;
      group.textTotal += Math.min(text.length, 4000);
      group.areaTotal += Math.min(rect.width * rect.height, 900000);
      if (text) group.uniqueTexts.add(text.toLowerCase());
    }

    return [...map.values()]
      .map(group => ({
        tag: group.tag,
        count: group.count,
        media: group.media,
        avgText: group.count ? group.textTotal / group.count : 0,
        avgArea: group.count ? group.areaTotal / group.count : 0,
        uniqueTextCount: group.uniqueTexts.size
      }))
      .filter(group => group.count >= 8 && group.count <= 160)
      .sort((a, b) => {
        const tagBonusA = /(card|message|post|sign|wish|entry)/.test(a.tag) ? 5000 : 0;
        const tagBonusB = /(card|message|post|sign|wish|entry)/.test(b.tag) ? 5000 : 0;
        const scoreA =
          tagBonusA +
          a.uniqueTextCount * 120 +
          a.media * 40 +
          Math.min(2500, a.avgText) +
          Math.min(2500, a.avgArea / 100);
        const scoreB =
          tagBonusB +
          b.uniqueTextCount * 120 +
          b.media * 40 +
          Math.min(2500, b.avgText) +
          Math.min(2500, b.avgArea / 100);
        return scoreB - scoreA;
      })
      .slice(0, 12);
  }, c);

  if (!groups.length) return null;

  console.log(
    "Angular component candidates: " +
    groups.map(g =>
      `${g.tag}=${g.count}/${g.uniqueTextCount} unique`
    ).join(", ")
  );

  let best = null;

  for (const group of groups) {
    const raw = await plausible(page, group.tag, c);
    if (raw.length < 8) continue;

    const seen = new Set();
    const kept = [];
    const rejected = [];

    for (const candidate of raw) {
      const key = normalizeMatchText(candidate.text || "");
      if (key && seen.has(key)) {
        rejected.push({
          index: candidate.index,
          reason: "exact component text duplicate",
          text: normalizeText(candidate.text).slice(0, 160)
        });
        continue;
      }
      if (key) seen.add(key);
      kept.push(candidate);
    }

    const mediaCards = kept.filter(x => x.imgCount > 0).length;
    const uniqueRatio = kept.length / Math.max(1, raw.length);
    const tagBonus = /(card|message|post|sign|wish|entry)/.test(group.tag) ? 10000 : 0;
    const score =
      tagBonus +
      kept.length * 300 +
      mediaCards * 20 +
      Math.round(uniqueRatio * 1000);

    const candidate = {
      selector: group.tag,
      raw,
      list: kept,
      rejected,
      score,
      angularReport:
        `${group.tag} raw=${raw.length} unique=${kept.length} media=${mediaCards}`
    };

    if (!best || candidate.score > best.score) {
      best = candidate;
    }
  }

  return best;
}

async function chooseSelector(page, c) {
  if ((c.cardSelector || "").trim()) {
    const s = c.cardSelector.trim();
    const result = await inspectSelector(page, s, c);
    if (!result.list.length) {
      throw new Error(`cardSelector '${s}' found no plausible Recocards.`);
    }
    return result;
  }

  // The current RecoCards board renders one post per mat-card. Select that
  // component directly: content-based deduplication can discard separate posts
  // whose messages happen to be identical or nearly identical.
  const componentSelector = "mat-card.example-card";
  const componentCount = await page.locator(componentSelector).count();
  if (componentCount >= 20) {
    const componentCards = await plausible(page, componentSelector, c);
    const replyCount = await page.getByRole("button", { name: /^Reply$/ }).count();
    // Closed/read-only boards may hide every Reply action while keeping the
    // same card components visible. A partial Reply set is still suspicious.
    if (componentCards.length === componentCount &&
        (replyCount === 0 || componentCount === replyCount)) {
      console.log(`Using RecoCards post components: ${componentCount} cards`);
      return {
        selector: componentSelector,
        raw: componentCards,
        list: componentCards,
        rejected: []
      };
    }
    throw new Error(
      `RecoCards component coverage incomplete: components=${componentCount}, ` +
      `plausible=${componentCards.length}, replyButtons=${replyCount}. ` +
      `No partial card set will be generated.`
    );
  }

  let best = null;

  for (const s of c.autoSelectors || []) {
    const result = await inspectSelector(page, s, c);
    const imageCards = result.list.filter(x => x.imgCount > 0).length;
    const score =
      result.list.length * 100 +
      imageCards * 5 -
      result.rejected.length;

    if (result.list.length >= 2 && (!best || score > best.score)) {
      best = { ...result, score };
    }
  }

  const isLegacy =
    /\/view\/b\//i.test(page.url()) ||
    /\/view\/b\//i.test(c.url || "");

  let replyCards = await replyCardDetector(page, c);
  let angular = await angularCardComponentFallback(page, c);
  let generic = await genericCardFallback(page, c);
  let union = await unionCardFallback(page, c);
  let broad = null;

  if (isLegacy) {
    broad = await legacyBroadDetector(page, c);
  }

  console.log(
    `Detection comparison: replyCards=${replyCards ? replyCards.list.length : 0}, ` +
    `angular=${angular ? angular.list.length : 0}, ` +
    `named=${best ? best.list.length : 0}, ` +
    `generic=${generic ? generic.list.length : 0}, ` +
    `union=${union ? union.list.length : 0}, ` +
    `legacyBroad=${broad ? broad.list.length : 0}`
  );

  const configuredMaxCards = Math.max(1, Number(c.maxCards) || 100);

  if (
    replyCards &&
    replyCards.list &&
    replyCards.list.length >= 20 &&
    replyCards.list.length <= configuredMaxCards
  ) {
    console.log(`Using Reply-card detector: ${replyCards.replyReport}`);
    return replyCards;
  }

  if (
    angular &&
    angular.list &&
    angular.list.length >= 20 &&
    angular.list.length <= configuredMaxCards
  ) {
    console.log(`Using Angular card component: ${angular.angularReport}`);
    return angular;
  }

  const options = [best, generic, union, broad].filter(
    x =>
      x &&
      x.list &&
      x.list.length &&
      x.list.length <= configuredMaxCards
  );

  options.sort((a, b) => b.list.length - a.list.length);

  if (options.length) return options[0];

  throw new Error(
    "No Recocards detected. See debug-page.png/card_detection.txt."
  );
}


function cleanAuthorValue(author, message = "") {
  const value = normalizeText(author || "");
  const body = normalizeText(message || "");

  if (!value) return "";
  if (value.length > 60) return "";

  const valueKey = normalizeMatchText(value);
  const bodyKey = normalizeMatchText(body);

  if (bodyKey && valueKey === bodyKey) return "";
  if (bodyKey && valueKey.length >= 24 && bodyKey.startsWith(valueKey)) return "";

  return value;
}

function authorFromCandidate(src) {
  const raw = String(src?.rawText || "");
  const lines = raw
    .split(/\r?\n/)
    .map(x => normalizeText(x))
    .filter(Boolean);

  if (lines.length < 2) return "Anonymous";

  const candidate = cleanAuthorValue(lines[0], lines.slice(1).join(" "));
  return candidate || "Anonymous";
}

function authorForDomCard(src, domIndex, dataDomComparison) {
  const match = (dataDomComparison || []).find(
    row => row.matchedDomIndex === domIndex
  );

  if (match) {
    const author = cleanAuthorValue(
      match.post?.author || "",
      match.post?.message || ""
    );

    return author || "Anonymous";
  }

  return authorFromCandidate(src);
}


function extractHttpLinksFromCandidate(src) {
  const found = [];
  const seen = new Set();

  const push = value => {
    if (!value) return;
    const url = String(value).trim();
    if (!/^https?:\/\//i.test(url)) return;
    if (url.length > 2048 || seen.has(url)) return;
    seen.add(url);
    found.push(url);
  };

  const raw = String(src?.rawText || src?.text || "");
  const matches = raw.match(/https?:\/\/[^\s<>"')\]]+/gi) || [];
  for (let url of matches) {
    url = url.replace(/[.,!?;:]+$/g, "");
    push(url);
  }

  for (const url of (src?.links || [])) {
    push(url);
  }

  return found.slice(0, 8);
}

function encodeManifestLinks(links) {
  return (links || [])
    .map(url => encodeURIComponent(String(url)))
    .join(",");
}

function decodeManifestLinks(encoded) {
  if (!encoded) return [];
  return String(encoded)
    .split(",")
    .filter(Boolean)
    .map(value => {
      try { return decodeURIComponent(value); }
      catch (_) { return ""; }
    })
    .filter(Boolean);
}

function manifestSafe(value) {
  return normalizeText(String(value || ""))
    .replace(/\|/g, "/")
    .slice(0, 120);
}

function stableId(text, index) {
  const normalized = normalizeText(text);
  const source = normalized.length ? normalized : `fallback-card-${index}`;
  return crypto.createHash("sha1").update(source).digest("hex").slice(0, 12);
}

function hashBuffer(buffer) {
  return crypto.createHash("sha1").update(buffer).digest("hex");
}

function atomicWrite(file, text) {
  const tmp = file + ".tmp";
  fs.writeFileSync(tmp, text, "utf8");
  fs.renameSync(tmp, file);
}


function loadPreviousManifest() {
  const file = path.join(OUT, "manifest.txt");
  if (!fs.existsSync(file)) return new Map();

  const map = new Map();

  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!line.trim()) continue;

    const parts = line.split("|");
    if (parts.length < 5) continue;

    const [
      order, id, filename, width, height,
      frames = "1", fps = "0", author = "", encodedLinks = ""
    ] = parts;

    map.set(id, {
      order: Number(order),
      id,
      filename,
      width: Number(width),
      height: Number(height),
      frameCount: Number(frames) || 1,
      fps: Number(fps) || 0,
      author,
      links: decodeManifestLinks(encodedLinks)
    });
  }

  return map;
}

function cachedFilesExist(card) {
  if (!card) return false;

  if (!fs.existsSync(path.join(OUT, card.filename))) return false;

  if ((card.frameCount || 1) <= 1) return true;

  for (let frame = 1; frame <= card.frameCount; frame++) {
    if (!fs.existsSync(path.join(OUT, frameFilename(card.id, frame)))) {
      return false;
    }
  }

  return true;
}

function frameFilename(id, frame) {
  return `card_${id}_f${String(frame).padStart(3, "0")}.png`;
}


async function resolveCardCaptureRoot(page, el, token, post) {
  const attr = "data-recocards-capture-root";
  await page.locator(`[${attr}]`).evaluateAll(nodes =>
    nodes.forEach(node => node.removeAttribute(attr))
  ).catch(() => {});

  const found = await el.evaluate((node, args) => {
    const norm = value => String(value || "").replace(/\s+/g, " ").trim().toLowerCase();
    const author = norm(args.author);
    const message = norm(args.message);
    const expectsMedia = Boolean(args.media);
    const probeSize = message.length >= 300 ? 80 : 120;
    const maxStart = Math.max(0, message.length - probeSize);
    const probeStarts = [0, Math.floor(maxStart * 0.5), maxStart];
    const probes = [];
    const seenProbes = new Set();

    for (const start of probeStarts) {
      const probe = message.slice(start, start + probeSize).trim();
      if (probe.length < 8 || seenProbes.has(probe)) continue;
      seenProbes.add(probe);
      probes.push(probe);
    }

    let current = node;
    let best = node;
    let bestScore = -1e9;

    for (let depth = 0; current && depth < 12; depth++, current = current.parentElement) {
      if (current === document.body || current === document.documentElement) break;

      const rect = current.getBoundingClientRect();
      if (
        rect.width < 120 || rect.height < 60 ||
        rect.width > 1000 || rect.height > 1800
      ) continue;

      const sourceCount = current.querySelectorAll("[data-recocards-card-source]").length;
      if (sourceCount > 1) continue;

      const style = getComputedStyle(current);
      const text = norm(current.innerText);
      const mediaCount = current.querySelectorAll("img,video,canvas").length;
      const bg = style.backgroundColor || "";
      const hasBg =
        style.backgroundImage !== "none" ||
        (bg && bg !== "transparent" && bg !== "rgba(0, 0, 0, 0)");
      const radius = parseFloat(style.borderRadius || "0") || 0;

      let score = 0;
      if (author && text.includes(author)) score += 900;

      let matchedProbes = 0;
      for (const probe of probes) {
        if (text.includes(probe)) matchedProbes++;
      }

      if (matchedProbes > 0) {
        score += 1100 + Math.min(300, (matchedProbes - 1) * 150);
      }

      if (mediaCount > 0) score += expectsMedia ? 680 : 180;
      if (expectsMedia && mediaCount === 0) score -= 500;
      if (hasBg) score += 260;
      if (radius > 0) score += 80;
      score -= depth * 5;
      score -= Math.max(0, mediaCount - 4) * 80;

      if (score > bestScore) {
        bestScore = score;
        best = current;
      }
    }

    best.setAttribute(args.attr, args.token);
    return true;
  }, {
    attr,
    token: String(token),
    author: post?.author || "",
    message: post?.message || "",
    media: post?.media || ""
  }).catch(() => false);

  if (!found) return el;
  return page.locator(`[${attr}="${String(token)}"]`).first();
}

async function prepareTransparentCapture(el) {
  await el.evaluate(node => {
    document.documentElement.style.background = "transparent";
    if (document.body) document.body.style.background = "transparent";
    let parent = node.parentElement;
    while (parent) {
      parent.style.background = "transparent";
      parent.style.backgroundColor = "transparent";
      parent.style.backgroundImage = "none";
      parent = parent.parentElement;
    }
  });
}

async function detectAnimation(el, c) {
  const samples = Math.max(2, Number(c.animationDetectionSamples) || 3);
  const delay = Math.max(50, Number(c.animationDetectionDelayMs) || 250);

  let firstHash = null;

  for (let i = 0; i < samples; i++) {
    const shot = await el.screenshot({ type: "png", omitBackground: true });
    const hash = hashBuffer(shot);

    if (firstHash === null) {
      firstHash = hash;
    } else if (hash !== firstHash) {
      return true;
    }

    if (i + 1 < samples) {
      await sleep(delay);
    }
  }

  return false;
}

function getAnimationCaptureConfig(c, author) {
  const baseFps = Math.max(1, Number(c.animationFps) || 8);
  const baseDuration = Math.max(0.5, Number(c.animationDurationSeconds) || 3);
  const baseMaxFrames = Math.max(2, Number(c.maxAnimationFrames) || 24);
  const normalizedAuthor = String(author || "").trim().toLowerCase();
  const overrides = c && typeof c.animationOverrides === "object" && c.animationOverrides
    ? c.animationOverrides
    : null;

  if (overrides) {
    for (const [name, value] of Object.entries(overrides)) {
      if (String(name || "").trim().toLowerCase() !== normalizedAuthor) continue;
      const fps = Math.max(1, Number(value.animationFps) || baseFps);
      const duration = Math.max(0.5, Number(value.animationDurationSeconds) || baseDuration);
      const maxFrames = Math.max(2, Number(value.maxAnimationFrames) || baseMaxFrames);
      return {
        fps,
        duration,
        maxFrames,
        forceAnimated: value.forceAnimated === true,
        frameCount: Math.max(2, Math.min(maxFrames, Math.round(fps * duration)))
      };
    }
  }

  return {
    fps: baseFps,
    duration: baseDuration,
    maxFrames: baseMaxFrames,
    forceAnimated: false,
    frameCount: Math.max(2, Math.min(baseMaxFrames, Math.round(baseFps * baseDuration)))
  };
}

function isGifUrl(url) {
  try {
    return /\.gif$/i.test(new URL(String(url)).pathname);
  } catch (_) {
    return /\.gif(?:$|[?#])/i.test(String(url || ""));
  }
}

async function captureAnimatedFrames(el, id, c, captureScale, author) {
  const animCfg = getAnimationCaptureConfig(c, author);
  const fps = animCfg.fps;
  const frameCount = animCfg.frameCount;

  const frameInterval = Math.max(20, 1000 / fps);
  const files = [];

  let box = await el.boundingBox();
  if (!box) {
    throw new Error("Animated card lost its bounding box.");
  }

  const captureStart = Date.now();

  for (let frame = 1; frame <= frameCount; frame++) {
    const filename = frameFilename(id, frame);

    await el.screenshot({
      path: path.join(OUT, filename),
      type: "png",
      omitBackground: true
    });

    files.push(filename);

    if (frame < frameCount) {
      const targetTime = captureStart + frame * frameInterval;
      const remaining = Math.round(targetTime - Date.now());
      if (remaining > 0) {
        await sleep(remaining);
      }
    }
  }

  return {
    frameCount,
    fps,
    files,
    width: Math.max(1, Math.round(box.width * captureScale)),
    height: Math.max(1, Math.round(box.height * captureScale))
  };
}

function cleanup(validFiles) {
  const keep = new Set(validFiles);

  for (const name of fs.readdirSync(OUT)) {
    const isCard =
      /^card_[a-f0-9]{12}\.png$/.test(name) ||
      /^card_[a-f0-9]{12}_f\d{3}\.png$/.test(name);

    if (isCard && !keep.has(name)) {
      try {
        fs.unlinkSync(path.join(OUT, name));
      } catch (_) {}
    }
  }
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });


  const birthdayLinkFileWatcher = startBirthdayLinkFileWatcher();

  const first = readCfg();
  const captureScale = Math.max(1, Number(first.captureScale) || 2);

  const browser = await chromium.launch({ headless: true });

  const ctx = await browser.newContext({
    viewport: first.viewport || { width: 1440, height: 1200 },
    deviceScaleFactor: captureScale
  });

  const page = await ctx.newPage();

  const boardDataCapture = await installBoardDataCapture(page);

  console.log("DunkOrSlam Birthday Book bridge");
  console.log("Board:", first.url);
  console.log(`Card capture scale: ${captureScale}x`);

  for (let bridgeRun = 0; bridgeRun < 1; bridgeRun++) {
    const c = readCfg();
    const started = Date.now();

    try {
      await page.goto(c.url, {
        waitUntil: "domcontentloaded",
        timeout: 45000
      });

      await sleep(c.waitAfterLoadMs || 3500);

      const legacyOpened = await enterLegacyBoardIfNeeded(page, c);

      console.log(
        legacyOpened
          ? "Legacy board: scrolling through full board to load all entries..."
          : "Board: scrolling through full board to load all entries..."
      );
      await fullyLoadBoardByScrolling(page, c);

      const boardData =
        await discoverBoardPosts(
          page,
          boardDataCapture.captured
        );

      if (boardData.best) {
        console.log(
          `Board data candidate: posts=${boardData.posts.length} ` +
          `path=${boardData.best.path}`
        );
      } else {
        console.log("Board data candidate: none found");
      }

      await hideNoise(page, c.hideSelectors);

      await page.screenshot({
        path: path.join(OUT, "debug-page.png"),
        fullPage: false
      });

      const chosen = await chooseSelector(page, c);
      const loc = page.locator(chosen.selector);

      console.log(
        `Card selector: ${chosen.selector} | raw=${chosen.raw.length} | accepted=${chosen.list.length} | rejected=${chosen.rejected.length}`
      );

      const dataDomComparison =
        compareDataPostsToDom(
          boardData.posts,
          chosen.list
        );

      const matchedDataPosts =
        dataDomComparison.filter(x => x.matchedDomIndex !== null).length;

      if (boardData.posts.length) {
        console.log(
          `Board data vs DOM: data=${boardData.posts.length}, ` +
          `matched=${matchedDataPosts}, missing=${boardData.posts.length - matchedDataPosts}`
        );
      }

      const previous = loadPreviousManifest();
      const animationCacheVersionFile = path.join(OUT, "animation_detection_version.txt");
      const animationCacheVersion = "2";
      const previousAnimationCacheVersion = fs.existsSync(animationCacheVersionFile)
        ? fs.readFileSync(animationCacheVersionFile, "utf8").trim()
        : "";
      const cards = [];
      const used = new Set();
      const validFiles = [];
      const configuredMaxCards = Math.max(1, Number(c.maxCards) || 100);
      const captureTarget = Math.min(chosen.list.length, configuredMaxCards);

      const reportLines = [
        `selector=${chosen.selector}`,
        `raw=${chosen.raw.length}`,
        `accepted=${chosen.list.length}`,
        `rejected=${chosen.rejected.length}`,
        `configured_max_cards=${configuredMaxCards}`,
        `capture_target=${captureTarget}`,
        `DATA_POSTS=${boardData.posts.length}`,
        `DATA_MATCHED_TO_DOM=${matchedDataPosts}`,
        `DATA_MISSING_FROM_DOM=${Math.max(0, boardData.posts.length - matchedDataPosts)}`,
        boardData.best
          ? `DATA_SOURCE=${boardData.best.source || ""}`
          : "DATA_SOURCE=",
        boardData.best
          ? `DATA_PATH=${boardData.best.path || ""}`
          : "DATA_PATH=",
        ""
      ];

      if (boardData.posts.length) {
        reportLines.push("BOARD DATA POSTS:");

        for (const row of dataDomComparison) {
          reportLines.push(
            `DATA ${row.dataIndex} matchedDom=${row.matchedDomIndex ?? "NONE"} score=${row.score} ` +
            `id=${row.post.id || ""} author=${normalizeText(row.post.author || "").slice(0,80)} ` +
            `message=${normalizeText(row.post.message || "").slice(0,180)} ` +
            `media=${normalizeText(row.post.media || "").slice(0,120)}`
          );
        }

        reportLines.push("");
      }

      reportLines.push("RAW DOM CANDIDATES:");
      chosen.raw.forEach((x, idx) => {
        reportLines.push(
          `RAW ${idx + 1} domIndex=${x.index} size=${Math.round(x.box.width)}x${Math.round(x.box.height)} ` +
          `images=${x.imgCount} authorGuess=${authorFromCandidate(x)} text=${normalizeText(x.text).slice(0, 700)}`
        );
      });

      reportLines.push("");
      reportLines.push("REJECTED DUPLICATE COMPARISONS:");

      for (const x of chosen.rejected) {
        const rejectedCandidate = chosen.raw.find(row => row.index === x.index);
        const winnerCandidate = chosen.raw.find(row => row.index === x.winnerIndex);

        reportLines.push(
          `REJECT domIndex=${x.index} keptDomIndex=${x.winnerIndex ?? "NONE"} ` +
          `reason=${x.reason} ratio=${Number(x.ratio || 0).toFixed(4)} delta=${x.delta ?? ""}`
        );
        reportLines.push(
          `  REJECT_AUTHOR=${rejectedCandidate ? authorFromCandidate(rejectedCandidate) : ""}`
        );
        reportLines.push(
          `  KEPT_AUTHOR=${winnerCandidate ? authorFromCandidate(winnerCandidate) : ""}`
        );
        reportLines.push(
          `  REJECT_TEXT=${normalizeText(x.text || "").slice(0, 1200)}`
        );
        reportLines.push(
          `  KEPT_TEXT=${normalizeText(x.winnerText || "").slice(0, 1200)}`
        );
      }

      reportLines.push("");
      reportLines.push("ACCEPTED DOM CANDIDATES:");
      chosen.list.forEach((x, idx) => {
        reportLines.push(
          `ACCEPT ${idx + 1} domIndex=${x.index} size=${Math.round(x.box.width)}x${Math.round(x.box.height)} ` +
          `images=${x.imgCount} authorGuess=${authorFromCandidate(x)} text=${normalizeText(x.text).slice(0, 700)}`
        );
      });

      reportLines.push("");

      await loc.evaluateAll((nodes, accepted) => {
        nodes.forEach(node => node.removeAttribute("data-recocards-card-source"));
        for (const item of accepted) {
          const node = nodes[item.index];
          if (node) node.setAttribute("data-recocards-card-source", String(item.order));
        }
      }, chosen.list.map((item, index) => ({ index: item.index, order: index + 1 }))).catch(() => {});

      for (let j = 0; j < captureTarget; j++) {
        const src = chosen.list[j];
        const sourceEl = loc.nth(src.index);
        const dataMatch = (dataDomComparison || []).find(
          row => row.matchedDomIndex === j + 1
        );
        const cardAuthor = authorForDomCard(src, j + 1, dataDomComparison);
        const el = await resolveCardCaptureRoot(
          page,
          sourceEl,
          `card-${j + 1}`,
          dataMatch?.post || null
        );

        try {
          await el.scrollIntoViewIfNeeded();
          await sleep(100);

          const b = await el.boundingBox();
          if (!b) continue;

          let id = stableId(src.text, j + 1);
          let salt = 1;

          while (used.has(id)) {
            id = stableId(src.text + `#${salt}`, j + 1);
            salt++;
          }

          used.add(id);

          const staticFilename = `card_${id}.png`;
          const cached = previous.get(id);

          const mediaHints = await el.evaluate(node => {
            const imgs = [...node.querySelectorAll("img")];
            const hasGifUrl = imgs.some(img => /\.gif(?:$|[?#])/i.test(img.currentSrc || img.src || ""));
            const hasVideo = node.querySelector("video") !== null;
            const hasCanvas = node.querySelector("canvas") !== null;
            return { hasGifUrl, hasVideo, hasCanvas, imageCount: imgs.length };
          }).catch(() => ({ hasGifUrl:false, hasVideo:false, hasCanvas:false, imageCount:0 }));
          const domAuthor = authorFromCandidate(src);
          const animationAuthor = domAuthor === "Anonymous" ? cardAuthor : domAuthor;
          const animationConfig = getAnimationCaptureConfig(c, animationAuthor);
          const hasGif = mediaHints.hasGifUrl || (src.mediaUrls || []).some(isGifUrl);
          const forceAnimated = animationConfig.forceAnimated || hasGif;
          const cacheHasRequiredAnimation = !forceAnimated || (
            cached && cached.frameCount > 1 &&
            (!animationConfig.forceAnimated || (
              cached.frameCount === animationConfig.frameCount &&
              cached.fps === animationConfig.fps
            ))
          );
          const cacheHasCurrentDetection =
            !cached || cached.frameCount > 1 || mediaHints.imageCount === 0 ||
            previousAnimationCacheVersion === animationCacheVersion;

          if (c.reuseCachedCards !== false && cacheHasRequiredAnimation &&
              cacheHasCurrentDetection && cachedFilesExist(cached)) {
            const reused = {
              order: j + 1,
              id,
              filename: cached.filename,
              width: cached.width,
              height: cached.height,
              frameCount: cached.frameCount,
              fps: cached.fps,
              author: manifestSafe(cardAuthor),
              links: extractHttpLinksFromCandidate(src).length
                ? extractHttpLinksFromCandidate(src)
                : (cached.links || [])
            };

            cards.push(reused);
            validFiles.push(reused.filename);

            if (reused.frameCount > 1) {
              for (let frame = 1; frame <= reused.frameCount; frame++) {
                validFiles.push(frameFilename(id, frame));
              }
            }

            reportLines.push(
              `CARD ${j + 1} id=${id} cached=yes animated=${reused.frameCount > 1 ? "yes" : "no"}`
            );

            continue;
          }

          await prepareTransparentCapture(el);

          await el.screenshot({
            path: path.join(OUT, staticFilename),
            type: "png",
            omitBackground: true
          });

          validFiles.push(staticFilename);

          const shouldProbeAnimation =
            mediaHints.hasVideo ||
            mediaHints.hasCanvas ||
            mediaHints.imageCount > 0;

          const animated = forceAnimated || (shouldProbeAnimation
            ? await detectAnimation(el, c)
            : false);

          if (animated) {
            const anim = await captureAnimatedFrames(
              el,
              id,
              c,
              captureScale,
              animationAuthor
            );

            validFiles.push(...anim.files);

            cards.push({
              order: j + 1,
              id,
              filename: staticFilename,
              width: anim.width,
              height: anim.height,
              frameCount: anim.frameCount,
              fps: anim.fps,
              author: manifestSafe(cardAuthor),
              links: extractHttpLinksFromCandidate(src)
            });

            reportLines.push(
              `CARD ${j + 1} id=${id} animated=yes frames=${anim.frameCount} fps=${anim.fps} ` +
              `source=${animationConfig.forceAnimated ? "override" : hasGif ? "gif" : "probe"} author=${manifestSafe(cardAuthor)}`
            );

            console.log(
              `  Card ${j + 1}: animation detected -> ${anim.frameCount} frames @ ${anim.fps} fps`
            );
          } else {
            cards.push({
              order: j + 1,
              id,
              filename: staticFilename,
              width: Math.max(1, Math.round(b.width * captureScale)),
              height: Math.max(1, Math.round(b.height * captureScale)),
              frameCount: 1,
              fps: 0,
              author: manifestSafe(cardAuthor),
              links: extractHttpLinksFromCandidate(src)
            });

            reportLines.push(
              `CARD ${j + 1} id=${id} animated=no author=${manifestSafe(cardAuthor)}`
            );
          }
        } catch (e) {
          console.error(`Card ${j + 1}: ${e.message}`);
        }
      }

      if (cards.length !== captureTarget) {
        reportLines.push(
          `CAPTURE_FAILED expected=${captureTarget} actual=${cards.length}`
        );
        atomicWrite(
          path.join(OUT, "card_detection.txt"),
          reportLines.join("\n") + "\n"
        );
        throw new Error(
          `Only ${cards.length} of ${captureTarget} cards captured; ` +
          `keeping the previous manifest. See card_detection.txt.`
        );
      }

      const manifest =
        cards
          .map(x =>
            `${x.order}|${x.id}|${x.filename}|${x.width}|${x.height}|${x.frameCount}|${x.fps}|${manifestSafe(x.author || "Birthday Spirit")}|${encodeManifestLinks(x.links || [])}`
          )
          .join("\n") + "\n";

      atomicWrite(path.join(OUT, "manifest.txt"), manifest);
      atomicWrite(path.join(OUT, "count.txt"), String(cards.length) + "\n");
      reportLines.push("");
      reportLines.push(`DETECTED_RECOCARDS=${chosen.list.length}`);
      reportLines.push(`CAPTURE_TARGET=${captureTarget}`);
      reportLines.push(`FINAL_RECOCARDS=${cards.length}`);

      if (cards.length !== captureTarget) {
        reportLines.push(
          `WARNING_CAPTURE_MISMATCH expected=${captureTarget} actual=${cards.length}`
        );
      }
      reportLines.push(
        `FINAL_ANIMATED=${cards.filter(x => x.frameCount > 1).length}`
      );

      atomicWrite(
        path.join(OUT, "card_detection.txt"),
        reportLines.join("\n") + "\n"
      );

      const boardDataLines = [
        `DATA_POSTS=${boardData.posts.length}`,
        boardData.best
          ? `BEST_SOURCE=${boardData.best.source || ""}`
          : "BEST_SOURCE=",
        boardData.best
          ? `BEST_PATH=${boardData.best.path || ""}`
          : "BEST_PATH=",
        boardData.best
          ? `BEST_ARRAY_LENGTH=${boardData.best.totalLength}`
          : "BEST_ARRAY_LENGTH=0",
        boardData.best
          ? `BEST_POSTLIKE_COUNT=${boardData.best.postLikeCount}`
          : "BEST_POSTLIKE_COUNT=0",
        `DOM_ACCEPTED=${chosen.list.length}`,
        `DATA_MATCHED_TO_DOM=${matchedDataPosts}`,
        `DATA_MISSING_FROM_DOM=${Math.max(0, boardData.posts.length - matchedDataPosts)}`,
        "",
        ...dataDomComparison.map(row =>
          `DATA ${row.dataIndex} matchedDom=${row.matchedDomIndex ?? "NONE"} score=${row.score} ` +
          `id=${row.post.id || ""} author=${normalizeText(row.post.author || "").slice(0,100)} ` +
          `message=${normalizeText(row.post.message || "").slice(0,240)} ` +
          `media=${normalizeText(row.post.media || "").slice(0,180)}`
        )
      ];

      atomicWrite(
        path.join(OUT, "board_data_detection.txt"),
        boardDataLines.join("\n") + "\n"
      );

      atomicWrite(animationCacheVersionFile, animationCacheVersion + "\n");

      cleanup(validFiles);

      const animatedCount = cards.filter(x => x.frameCount > 1).length;

      console.log(
        `[${new Date().toLocaleTimeString()}] ${cards.length} unique Cards ready (${animatedCount} animated).`
      );
    } catch (e) {
      console.error("[Bridge]", e.message);
    }

    console.log("Board import complete. No periodic refresh is configured.");

  }

  await browser.close();

  console.log("Board import complete. No periodic board refresh is configured.");
  console.log("Birthday Book link helper remains active while this window is open.");

  await new Promise(() => {});
})().catch(e => {
  console.error(e);
  process.exit(1);
});
