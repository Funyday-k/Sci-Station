"use strict";
(() => {
  const segmenter = typeof Intl.Segmenter === "function"
    ? new Intl.Segmenter(undefined, {granularity: "grapheme"}) : null;
  const graphemes = text => segmenter ? Array.from(segmenter.segment(text), part => part.segment) : Array.from(text);
  const codePoints = text => Array.from(text).length;
  const fieldKey = (target, field) => JSON.stringify([target, field]);
  const palette = [
    ["#1456a6", "#a5ccff"], ["#8a360a", "#ffc190"], ["#68409d", "#d8baff"], ["#006459", "#90ead8"],
    ["#9d2d55", "#ffacc8"], ["#4e630e", "#d4e489"], ["#825000", "#ffce7f"], ["#3b566d", "#b0d6f0"],
  ];
  const messages = {live: "正在编辑", settling: "等待确认", confirmed: "已确认编辑", draft: "起草"};
  const stickyMs = 2400;
  const settlingMs = 900;

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  function diff(before, after, complete = true) {
    const left = graphemes(before);
    const right = graphemes(after);
    let first = 0;
    while (first < left.length && first < right.length && left[first] === right[first]) first++;
    let lastLeft = left.length;
    let lastRight = right.length;
    if (complete) {
      while (lastLeft > first && lastRight > first && left[lastLeft - 1] === right[lastRight - 1]) {
        lastLeft--; lastRight--;
      }
    }
    const old = left.slice(first, lastLeft);
    const next = right.slice(first, lastRight);
    const width = next.length + 1;
    const scores = new Uint16Array((old.length + 1) * width);
    for (let i = old.length - 1; i >= 0; i--) {
      for (let j = next.length - 1; j >= 0; j--) {
        const cell = i * width + j;
        scores[cell] = old[i] === next[j] ? scores[cell + width + 1] + 1
          : Math.max(scores[cell + width], scores[cell + 1]);
      }
    }
    const parts = [];
    function append(kind, text) {
      if (!text) return;
      const previous = parts.at(-1);
      if (previous?.kind === kind) previous.text += text;
      else parts.push({kind, text});
    }
    append("same", left.slice(0, first).join(""));
    let i = 0;
    let j = 0;
    while (i < old.length && j < next.length) {
      const cell = i * width + j;
      if (old[i] === next[j]) {
        append("same", old[i++]);
        j++;
      } else if (!complete && scores[cell] === 0) break;
      else if (scores[cell + width] >= scores[cell + 1]) append("delete", old[i++]);
      else append("insert", next[j++]);
    }
    append("insert", next.slice(j).join(""));
    // The suffix not yet written by the provider is still canonical text.
    append(complete ? "delete" : "tail", old.slice(i).join(""));
    append("same", left.slice(lastLeft).join(""));
    return parts;
  }

  function mark(node, target, field, writeCanonical) {
    const canonical = element(field === "title" ? "span" : "div");
    canonical.dataset.boardCanonical = "";
    canonical.append(...node.childNodes);
    node.dataset.boardCursorTarget = target;
    node.dataset.boardCursorField = field;
    node.append(canonical);
    return {canonical, writeCanonical};
  }

  function fieldsOf(session) {
    const board = session?.board;
    const fields = new Map();
    if (board?.state !== "published") return fields;
    const put = (target, field, source) => fields.set(fieldKey(target, field), {
      target, field, text: source[field] || "", version: source.version || 0,
      seat: source.source_seat, round: source.source_round || 0,
    });
    put("board", "title", board);
    for (const module of board.modules || []) {
      put(module.id, "title", module);
      if (["materials", "note"].includes(module.kind)) put(module.id, "body", module);
    }
    return fields;
  }

  function mount({root, pending, seatName}) {
    const bindings = new WeakMap();
    const paintings = new WeakMap();
    const paintedLanes = new WeakMap();
    const paintedTokens = new WeakMap();
    const laneSignatures = new WeakMap();
    const pendingCards = new Map();
    const live = new Map();
    const settled = new Map();
    let session = null;
    let canonical = new Map();
    let lastSequence = -1;
    let timer;
    let latestSeats = new Set();

    function register(node, target, field, text, writeCanonical) {
      bindings.set(node, {...mark(node, target, field, writeCanonical), text});
    }

    function colorAndName(lane, entry) {
      const seats = session.members?.length ? session.members.map(member => member.id) : session.seats || [];
      const index = seats.indexOf(entry.seat);
      if (index < 0) return false;
      const hue = (328 + (index - palette.length) * 137.508) % 360;
      const [light, dark] = palette[index] || [`oklch(41% .15 ${hue})`, `oklch(82% .12 ${hue})`];
      lane.style.setProperty("--board-collab-light", light);
      lane.style.setProperty("--board-collab-dark", dark);
      return true;
    }

    function paintCursor(pin, entry) {
      const name = seatName(entry.seat, session);
      pin.dataset.boardCollaborator = entry.seat;
      pin.setAttribute("role", "img");
      pin.setAttribute("aria-label", `${name} ${messages[entry.phase]}`);
      if (!pin.firstChild) {
        const label = element("span", "board-collab-label");
        label.setAttribute("aria-hidden", "true");
        pin.append(label);
      }
      if (pin.firstChild.textContent !== name) pin.firstChild.textContent = name;
      pin.title = `${name} · ${messages[entry.phase]}`;
    }

    function splitAt(text, point) {
      let size = 0;
      let boundary = 0;
      for (const grapheme of graphemes(text)) {
        if (size >= point) break;
        size += codePoints(grapheme);
        boundary += grapheme.length;
      }
      return [text.slice(0, boundary), text.slice(boundary)];
    }

    function nearestChange(parts, offset) {
      let position = 0;
      let best = null;
      for (const [index, part] of parts.entries()) {
        const length = part.kind === "delete" ? 0 : codePoints(part.text);
        if (part.kind === "insert" || part.kind === "delete") {
          const point = Math.min(length, Math.max(0, offset - position));
          const distance = Math.abs(offset - position - point);
          if (!best || distance <= best.distance) best = {index, point, distance};
        }
        position += length;
      }
      if (best) return best;
      position = 0;
      for (const [index, part] of parts.entries()) {
        const length = codePoints(part.text);
        if (position + length >= offset) return {index, point: Math.max(0, offset - position)};
        position += length;
      }
      return {index: -1, point: 0};
    }

    function tokensFor(entry) {
      const tokens = [];
      let offset = 0;
      const provisional = entry.phase === "live" || entry.phase === "settling";
      if (entry.phase === "draft") return [{kind: "cursor", key: "cursor"}];
      const parts = diff(entry.before, entry.text, entry.complete);
      const showCursor = entry.active !== false;
      const position = showCursor && nearestChange(parts, entry.offset);
      function appendToken(kind, text, width = codePoints(text)) {
        tokens.push({kind, text, key: JSON.stringify([kind, offset, text])});
        offset += width;
      }
      function appendText(text, kind) {
        if (!text) return;
        if (kind === "insert") {
          for (const glyph of graphemes(text)) appendToken(kind, glyph);
        } else appendToken("text", text);
      }
      for (const [index, part] of parts.entries()) {
        const contains = position?.index === index;
        const [left, right] = contains ? splitAt(part.text, position.point) : [part.text, ""];
        if (part.kind === "delete") {
          if (provisional) appendToken("delete", part.text, 0);
          if (contains) tokens.push({kind: "cursor", key: "cursor"});
          continue;
        }
        appendText(left, part.kind);
        if (contains) tokens.push({kind: "cursor", key: "cursor"});
        appendText(right, part.kind);
      }
      if (position?.index === -1) tokens.push({kind: "cursor", key: "cursor"});
      if (provisional && !showCursor) tokens.push({kind: "passive", key: "passive"});
      return tokens;
    }

    function reconcileChildren(parent, previous, items) {
      const next = new Map(items);
      for (const [key, node] of previous) if (!next.has(key)) node.remove();
      let cursor = parent.firstChild;
      for (const node of next.values()) {
        if (cursor === node) cursor = cursor.nextSibling;
        else parent.insertBefore(node, cursor);
      }
      return next;
    }

    function makeToken(token, entry) {
      if (token.kind === "text") return document.createTextNode(token.text);
      if (token.kind === "cursor") return element("span", "board-collab-cursor");
      if (token.kind === "passive") return element("span", "board-collab-passive");
      const insertion = token.kind === "insert";
      const highlight = element(insertion ? "ins" : "del", "board-collab-change", token.text);
      highlight.dataset.boardLiveChange = token.kind;
      if (insertion && /\S/u.test(token.text) && (entry.phase === "live" || (entry.phase === "confirmed" && !entry.streamed)))
        highlight.classList.add("board-ink-in");
      return highlight;
    }

    function paintLanes(parent, entries) {
      const previousLanes = paintedLanes.get(parent) || new Map();
      const nextLanes = [];
      for (const entry of entries) {
        const lane = previousLanes.get(entry.seat) || element("span", "board-collab-lane");
        if (!colorAndName(lane, entry)) continue;
        nextLanes.push([entry.seat, lane]);
        const signature = JSON.stringify([entry.phase, entry.before, entry.text, entry.complete,
          entry.offset, entry.active, seatName(entry.seat, session)]);
        if (laneSignatures.get(lane) === signature) continue;
        laneSignatures.set(lane, signature);
        lane.dataset.boardLivePhase = entry.phase;
        lane.dataset.boardCollaboratorLane = entry.seat;
        const previousTokens = paintedTokens.get(lane) || new Map();
        // The pin moves around the existing glyphs, so their CSS animations stay attached.
        previousTokens.get("cursor")?.remove();
        const nextTokens = tokensFor(entry).map(token => {
          const piece = previousTokens.get(token.key) || makeToken(token, entry);
          if (token.kind === "cursor") paintCursor(piece, entry);
          if (token.kind === "passive") {
            const name = seatName(entry.seat, session);
            if (piece.textContent !== name) piece.textContent = name;
            piece.setAttribute("aria-label", `${name} 未确认`);
          }
          return [token.key, piece];
        });
        paintedTokens.set(lane, reconcileChildren(lane, previousTokens, nextTokens));
      }
      paintedLanes.set(parent, reconcileChildren(parent, previousLanes, nextLanes));
    }

    function selected(node) {
      const selection = window.getSelection();
      return Boolean(selection && !selection.isCollapsed &&
        (node.contains(selection.anchorNode) || node.contains(selection.focusNode)));
    }

    function hasCanonicalChanges(binding, field) {
      return binding && binding.text !== field.text;
    }

    function updateField(node, field, entries) {
      const binding = bindings.get(node);
      if (!binding || selected(node)) return;
      if (hasCanonicalChanges(binding, field)) {
        if (binding.writeCanonical) binding.writeCanonical(binding.canonical, field.text);
        else binding.canonical.textContent = field.text;
        binding.text = field.text;
      }
      const signature = JSON.stringify(entries);
      const previous = paintings.get(node);
      if (previous?.signature === signature || (!previous && !entries.length)) return;
      if (!entries.length) {
        previous?.overlay.remove();
        paintings.delete(node);
        binding.canonical.hidden = false;
        delete node.dataset.boardFieldPreview;
        return;
      }
      const drafted = entries[0].phase === "draft";
      const overlay = previous?.overlay || element(drafted || field.field === "title" ? "span" : "div", "board-collab-overlay");
      paintLanes(overlay, entries);
      const paragraph = drafted && binding.canonical.querySelector("p.board-prose");
      const destination = paragraph || node;
      if (overlay.parentNode !== destination) destination.append(overlay);
      binding.canonical.hidden = !drafted;
      node.dataset.boardFieldPreview = entries[0].phase;
      paintings.set(node, {signature, overlay});
    }

    function readingAnchor() {
      if (!root.scrollTop || root.hidden) return null;
      const top = root.getBoundingClientRect().top;
      return [...root.querySelectorAll("[data-board-anchor]")].find(node => node.getBoundingClientRect().bottom > top + 4);
    }

    function paint() {
      if (!session || session.board?.state !== "published") return;
      const anchor = readingAnchor();
      const top = anchor?.getBoundingClientRect().top;
      const grouped = new Map();
      const notes = new Map();
      for (const lane of live.values()) {
        for (const record of lane.fields.values()) {
          const key = fieldKey(record.target_id, record.field);
          const field = canonical.get(key);
          const newNote = record.op === "add_note";
          if ((!field && !newNote) || (field && field.version !== record.base_version)) continue;
          const before = field?.text || "";
          if (before === record.text && (record.complete || !record.active)) continue;
          const phase = latestSeats.has(record.seat) ? "live" : "settling";
          const entry = {...record, before, phase};
          const target = newNote ? notes : grouped;
          const bucket = newNote ? record.target_id : key;
          if (!target.has(bucket)) target.set(bucket, []);
          target.get(bucket).push(entry);
        }
      }
      for (const node of root.querySelectorAll("[data-board-cursor-field]")) {
        const key = fieldKey(node.dataset.boardCursorTarget, node.dataset.boardCursorField);
        const field = canonical.get(key);
        if (!field) continue;
        if (grouped.has(key)) updateField(node, field, grouped.get(key));
        else if (settled.has(key)) updateField(node, field, [settled.get(key)]);
        else updateField(node, field, []);
      }
      for (const [id, card] of pendingCards) {
        if (!notes.has(id)) {
          card.node.remove();
          pendingCards.delete(id);
        }
      }
      for (const [id, entries] of notes) {
        let card = pendingCards.get(id);
        if (!card) {
          const node = element("section", "board-collab-note");
          node.dataset.boardPendingNote = id;
          node.setAttribute("aria-label", "未确认的讨论笔记");
          node.append(element("p", "board-collab-note-status", "笔记草稿"));
          const title = element("div", "board-collab-note-title");
          const body = element("div", "board-collab-note-body");
          node.append(title, body);
          pending.append(node);
          card = {node, title, body, signature: ""};
          pendingCards.set(id, card);
        }
        const signature = JSON.stringify(entries);
        if (card.signature === signature || selected(card.node)) continue;
        card.signature = signature;
        for (const field of ["title", "body"])
          paintLanes(card[field], entries.filter(entry => entry.field === field));
      }
      if (anchor?.isConnected) root.scrollTop += anchor.getBoundingClientRect().top - top;
    }

    function armTimer() {
      clearTimeout(timer);
      const expiries = [...settled.values()].map(entry => entry.expires)
        .concat([...live.values()].map(lane => lane.expires).filter(Boolean));
      if (expiries.length) timer = setTimeout(() => {
        const now = Date.now();
        for (const [key, entry] of settled) if (entry.expires <= now) settled.delete(key);
        for (const [seat, lane] of live) if (lane.expires && lane.expires <= now) live.delete(seat);
        paint();
        armTimer();
      }, Math.max(0, Math.min(...expiries) - Date.now()));
    }

    function confirmed(key, field, before, phase = "confirmed", streamed = false) {
      settled.set(key, {
        phase, seat: field.seat, before, text: field.text, complete: true, streamed,
        offset: codePoints(field.text), expires: Date.now() + stickyMs,
      });
    }

    function sync(next) {
      const previous = canonical;
      const changedSession = session?.id !== next.id;
      if (changedSession) clear();
      session = next;
      canonical = fieldsOf(next);
      if (previous.size && !changedSession) for (const [key, field] of canonical) {
        const last = previous.get(key);
        if (last?.text === field.text) continue;
        if (field.seat && field.seat !== "user" && field.version > (last?.version || 0) && field.round > 0) {
          const candidate = live.get(field.seat)?.fields.get(field.field);
          const streamed = candidate?.round === field.round && (candidate.target_id === field.target || candidate.op === "add_note");
          confirmed(key, field, last?.text || "", "confirmed", streamed);
        } else settled.delete(key);
      }
      for (const [seat, lane] of live) {
        const recent = [...lane.fields.values()][0];
        const field = recent && canonical.get(fieldKey(recent.target_id, recent.field));
        const inserted = recent?.op === "add_note" && [...canonical.keys()].some(key => {
          const next = canonical.get(key);
          return !previous.has(key) && next.seat === seat && next.round === recent.round;
        });
        if (!canonical.size || next.status !== "running" || inserted || (field && field.version !== recent.base_version))
          live.delete(seat);
      }
      paint();
      armTimer();
    }

    function draft(target) {
      const body = canonical.get(fieldKey(target, "body"));
      const field = body?.text ? body : canonical.get(fieldKey(target, "title"));
      if (!field?.seat || field.seat === "user" || !field.text) return;
      const key = fieldKey(target, field.field);
      confirmed(key, field, "", "draft");
      paint();
      armTimer();
    }

    function setPresence(snapshot) {
      if (!snapshot) {
        live.clear();
        latestSeats.clear();
        lastSequence = -1;
        paint();
        armTimer();
        return;
      }
      if (snapshot.session_id !== session?.id || session.status !== "running" ||
          session.board?.state !== "published" || snapshot.seq <= lastSequence) return;
      lastSequence = snapshot.seq;
      latestSeats = new Set();
      const seats = session.members?.length ? session.members.map(member => member.id) : session.seats || [];
      for (const record of snapshot.cursors || []) {
        if (!seats.includes(record.seat) || record.seat === "user" || !["title", "body"].includes(record.field) ||
            typeof record.text !== "string" || codePoints(record.text) > (record.field === "title" ? 80 : 800)) continue;
        latestSeats.add(record.seat);
        const identity = JSON.stringify([record.round, record.op, record.target_id, record.base_version]);
        let lane = live.get(record.seat);
        if (!lane || lane.identity !== identity) {
          lane = {identity, fields: new Map(), expires: 0};
          live.set(record.seat, lane);
        }
        lane.expires = 0;
        for (const field of lane.fields.values()) field.active = false;
        if (record.field === "body" && typeof record.title === "string" && codePoints(record.title) <= 80) {
          lane.fields.set("title", {...record, field: "title", text: record.title, offset: codePoints(record.title),
            active: false, complete: true});
        }
        const offset = Math.min(codePoints(record.text), Math.max(0, record.offset ?? codePoints(record.text)));
        lane.fields.set(record.field, {...record, offset, active: true, complete: record.complete === true});
      }
      for (const [seat, lane] of live) {
        if (!latestSeats.has(seat) && !lane.expires) lane.expires = Date.now() + settlingMs;
      }
      paint();
      armTimer();
    }

    function clear() {
      setPresence(null);
      clearTimeout(timer);
      settled.clear();
      session = null;
      canonical = new Map();
      pending.replaceChildren();
      pendingCards.clear();
    }

    document.addEventListener("selectionchange", paint);
    return {register, sync, draft, setPresence, clear};
  }

  window.RoundtableBoardCursors = Object.freeze({mount, diff});
})();
