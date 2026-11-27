(() => {
  'use strict';
  const by = id => document.getElementById(id);
  const inputs = new URLSearchParams(location.search);
  const paperID = inputs.get('paper') || '';
  const projectID = inputs.get('project') || '';
  const apiRoot = '/api/research/papers/' + encodeURIComponent(paperID);
  let paper, annotations = [], selection = null, currentPage = 1, pageCount = 0;
  let pageData = null, requestNumber = 0, searchNumber = 0, zoom = 1, found = null;
  let projects = [], sessions = [], savedNote = '', noteRevision = 0, editingNote = false;
  let nativeAvailable = false, editingAnnotation = null, savingNote = false;
  let trackedPosition = false, pendingPosition = null, writingPosition = false, positionTimer;
  let searchResults = [], searchedTerm = '', focusedResult = -1;
  const recognized = new Map();

  function scrollExtent() {
    const viewport = by('viewport');
    return Math.max(0, viewport.scrollHeight - viewport.clientHeight) || 0;
  }
  function rememberPosition(immediate = false) {
    if (!trackedPosition || !pageData || !paper.file_sha256)
      return;
    const extent = scrollExtent();
    pendingPosition = {
      sourceHash: paper.file_sha256,
      page: currentPage,
      zoom,
      scroll: extent ? Math.min(1, Math.max(0, by('viewport').scrollTop / extent)) : 0
    };
    clearTimeout(positionTimer);
    if (immediate)
      void flushPosition();
    else
      positionTimer = setTimeout(flushPosition, 140);
  }
  async function flushPosition() {
    if (!pendingPosition || writingPosition)
      return;
    const position = pendingPosition;
    pendingPosition = null;
    writingPosition = true;
    try {
      await fetchJSON(apiRoot + '/reading-position', 'POST', position, {keepalive:true});
    } catch (e) {
      if (!pendingPosition)
        message('未保存阅读位置。' + errorText(e));
    } finally {
      writingPosition = false;
      void flushPosition();
    }
  }
  const text = (zh, en) => window.SciStationI18n?.text(zh, en) ?? zh;
  const local = (key, zh, en, ...args) => window.SciStationI18n?.message?.(key, ...args) ?? text(zh, en);
  const pageLabel = page => local('readerPageFormat', `第 ${page} 页`, `Page ${page}`, page);
  const message = text => {
    by('message').textContent = text;
  };
  const errorText = error => error?.message || String(error);
  const node = (tag, text, cls) => {
    const el = document.createElement(tag);
    if (text != null)
      el.textContent = text;
    if (cls)
      el.className = cls;
    return el;
  };
  const button = (text, callback, cls) => {
    const el = node('button', text, cls);
    el.type = 'button';
    el.addEventListener('click', () => {
      Promise.resolve(callback()).catch(e => message(errorText(e)));
    });
    return el;
  };
  async function fetchJSON(path, method = 'GET', payload, extra = {}) {
    const options = {...extra, method, cache: 'no-store', headers: method === 'GET' ? {} : {'X-Roundtable': '1'}};
    if (payload !== undefined) {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(payload);
    }
    const response = await fetch(path, options);
    if (!response.ok) {
      const raw = await response.text();
      let why = raw;
      try {
        const body = JSON.parse(raw);
        why = body.error || body.message || raw;
      } catch {
      }
      const err = new Error(why.trim() || '请求失败');
      err.status = response.status;
      throw err;
    }
    return response.status === 204 ? null : response.json();
  }
  function displayEmpty(text, link) {
    by('empty').replaceChildren(node('p', text));
    if (link) {
      const a = node('a', '打开 PDF 原件 ↗');
      a.href = apiRoot + '/pdf';
      a.target = '_blank';
      a.rel = 'noopener';
      by('empty').append(a);
    }
    by('empty').hidden = false;
    by('pageSurface').hidden = true;
  }
  function place(el, b) {
    el.style.left = (b.x * 100) + '%';
    el.style.top = (b.y * 100) + '%';
    el.style.width = (b.width * 100) + '%';
    el.style.height = (b.height * 100) + '%';
  }
  function paintMarks() {
    const layer = by('highlights'), frag = document.createDocumentFragment();
    const draw = (r, kind) => {
      const el = node('span', null, 'mark ' + kind);
      place(el, r);
      frag.append(el);
    };
    for (const a of annotations)
      if (a.page === currentPage)
        (a.rects || []).forEach(r => draw(r, a.kind));
    if (found && pageData && found.page === currentPage)
      pageData.words.filter(w => w.start < found.end && w.end > found.start)
          .forEach(w => draw(w.box, 'found'));
    layer.replaceChildren(frag);
  }
  let fontContext = null;
  function sizeWords() {
    if (!pageData || !by('pageSurface').clientWidth)
      return;
    if (!fontContext)
      fontContext = document.createElement('canvas').getContext('2d');
    const height = by('pageSurface').clientHeight, width = by('pageSurface').clientWidth;
    const children = by('textLayer').children;
    pageData.words.forEach((word, i) => {
      const e = children[i];
      if (!e)
        return;
      const px = Math.max(1, word.box.height * height);
      e.style.fontSize = px + 'px';
      fontContext.font = px + 'px serif';
      const measured = fontContext.measureText(word.text).width || 1;
      e.style.transform = 'scaleX(' + Math.max(.01, word.box.width * width / measured) + ')';
    });
  }
  function applyZoom() {
    const viewport = by('viewport');
    const padding = Number.parseFloat(getComputedStyle(viewport).paddingLeft) || 0;
    by('pageSurface').style.width = Math.max(140, (viewport.clientWidth - 2 * padding) * zoom) + 'px';
    by('pageSurface').style.maxWidth = 'none';
    by('fit').textContent = Math.abs(zoom - 1) < .01 ? text('适宽', 'Fit width') : Math.round(zoom * 100) + '%';
    sizeWords();
  }
  function updatePageControls() {
    by('pageNo').value = currentPage;
    by('pageNo').max = pageCount || 1;
    by('count').textContent = pageCount ? '/ ' + pageCount : '';
    by('prev').disabled = !nativeAvailable || currentPage <= 1;
    by('next').disabled = !nativeAvailable || currentPage >= pageCount;
    ['pageNo', 'fit', 'smaller', 'larger', 'findButton', 'regionButton'].forEach(
        k => by(k).disabled = !nativeAvailable);
  }
  window.SciShellReader=()=>{
    if(!paper)return null;
    const quote=selection?.selected_text || "";
    const idx=selection?.selectionStart;
    const valid=Boolean(quote && pageData && Number.isInteger(idx) && pageData.text.slice(idx,idx+quote.length)===quote);
    const offset=valid ? Array.from(pageData.text.slice(0,idx).replace(/\r\n?/g,"\n")).length : 0;
    return {id:paper.id,title:paper.title,page:paper.has_pdf?currentPage:0,quote,
      citation:valid ? {kind:"paper",id:paperID,page:currentPage,hash:paper.file_sha256,quote,offset} : null};
  };
  function resetSelection() {
    selection = null;
    editingAnnotation = null;
    by('selectionBox').hidden = true;
    by('handoff').disabled = true;
    by('addHighlight').disabled = true;
    by('comment').value = '';
    window.SciContextRail?.update();
  }
  function hasAnnotationDraft() {
    return Boolean(selection && (by('comment').value !== (selection.note || '') ||
        by('kind').value !== (selection.kind || 'highlight')));
  }
  function activateSelected(value, editing = false, revision = 0) {
    if (hasAnnotationDraft()) {
      message(text('先保存或取消当前批注草稿。', 'Save or cancel the current annotation draft first.'));
      return false;
    }
    selection = value;
    editingAnnotation = editing ? {id:value.id, revision} : null;
    by('selectedText').textContent = value.selected_text || `${pageLabel(value.page)} · ${text('已选原文区域', 'Selected region')}`;
    by('selectionBox').hidden = false;
    by('handoff').disabled = !value.selected_text;
    by('addHighlight').disabled = false;
    by('comment').value = value.note || '';
    by('kind').value = value.kind || 'highlight';
    updateSelectionLabels();
    window.SciContextRail?.update();
    return true;
  }
  function updateSelectionLabels() {
    by('saveSelection').textContent = editingAnnotation
      ? local('readerSaveChanges', '保存修改', 'Save changes')
      : local('readerSaveAnnotation', '保存批注', 'Save annotation');
    by('selectionPage').textContent = selection ? pageLabel(selection.page) : '';
  }
  function collectSelection() {
    const s = window.getSelection();
    if (!s || !s.rangeCount || s.isCollapsed)
      return;
    const r = s.getRangeAt(0), layer = by('textLayer');
    if (!layer.contains(r.startContainer) || !layer.contains(r.endContainer))
      return;
    const text = s.toString().trim();
    if (!text || !pageData)
      return;
    const parts = Array.from(layer.children).filter(el => r.intersectsNode(el));
    if (!parts.length)
      return;
    const bounds = layer.getBoundingClientRect(), rects = [];
    for (const el of parts) {
      const part = document.createRange();
      part.selectNodeContents(el);
      if (el.contains(r.startContainer))
        part.setStart(r.startContainer, r.startOffset);
      if (el.contains(r.endContainer))
        part.setEnd(r.endContainer, r.endOffset);
      const b = part.getBoundingClientRect();
      const left = Math.max(bounds.left, b.left), right = Math.min(bounds.right, b.right);
      const top = Math.max(bounds.top, b.top), bottom = Math.min(bounds.bottom, b.bottom);
      if (right > left && bottom > top) {
        const rect = {
          x: (left - bounds.left) / bounds.width,
          y: (top - bounds.top) / bounds.height,
          width: (right - left) / bounds.width,
          height: (bottom - top) / bounds.height
        };
        const last = rects[rects.length - 1];
        if (last && Math.abs(last.y - rect.y) < .003 && Math.abs(last.height - rect.height) < .004 &&
            rect.x >= last.x && rect.x - (last.x + last.width) < .015) {
          last.width = rect.x + rect.width - last.x;
        } else
          rects.push(rect);
      }
    }
    if (!rects.length)
      return;
    // Reconstruct source whitespace between consecutive words; WebKit selection
    // may insert line breaks between absolutely positioned spans.
    const i = Number(parts[0].dataset.i), j = Number(parts[parts.length - 1].dataset.i);
    const first = pageData.words[i], last = pageData.words[j];
    const start = first.start +
        (r.startContainer.nodeType === 3 && parts[0].contains(r.startContainer) ? r.startOffset : 0);
    const end = last.start +
        (r.endContainer.nodeType === 3 && parts[parts.length - 1].contains(r.endContainer) ?
             r.endOffset :
             last.text.length);
    const sourceText = pageData.text.slice(start, end);
    const quote = sourceText.trim();
    if (!quote)
      return;
    const selectionStart = start + sourceText.length - sourceText.trimStart().length;
    const selectionEnd = selectionStart + quote.length;
    if (selection && !editingAnnotation && selection.page === currentPage &&
        selection.selectionStart === selectionStart && selection.selectionEnd === selectionEnd)
      return;
    activateSelected({
      page: currentPage, selected_text: quote, selectionStart, selectionEnd, ocr: Boolean(pageData.ocr),
      rects, kind: 'highlight', color: '#edc947', note: ''
    });
  }
  async function goPage(number, {restore = false, track = true, scroll = 0, ocr = false} = {}) {
    if (!nativeAvailable || !Number.isFinite(number))
      return;
    const page = Math.max(1, Math.min(pageCount, Math.trunc(number)));
    setRegionMode(false);
    currentPage = page;
    const ticket = ++requestNumber;
    if (!hasAnnotationDraft())
      resetSelection();
    trackedPosition = track;
    pageData = null;
    by('pageStatus').textContent = '正在读取第 ' + page + ' 页…';
    updatePageControls();
    by('textLayer').replaceChildren();
    by('highlights').replaceChildren();
    by('pageImage').removeAttribute('src');
    by('pageSurface').hidden = true;
    try {
      const data = recognized.get(page) || await fetchJSON(apiRoot + '/pages/' + page + (ocr ? '/ocr' : ''));
      if (ocr)
        recognized.set(page, data);
      if (ticket !== requestNumber)
        return;
      const image = new Image();
      image.alt = 'PDF 第 ' + page + ' 页';
      image.src = apiRoot + '/pages/' + page + '/image';
      await image.decode();
      if (ticket !== requestNumber)
        return;
      const frag = document.createDocumentFragment();
      data.words.forEach((w, i) => {
        const el = node('span', w.text);
        el.dataset.i = i;
        el.style.left = w.box.x * 100 + '%';
        el.style.top = w.box.y * 100 + '%';
        el.style.fontFamily = 'serif';
        frag.append(el);
        if (i + 1 < data.words.length)
          frag.append(document.createTextNode(data.text.slice(w.end, data.words[i + 1].start)));
      });
      pageData = data;
      by('textLayer').replaceChildren(frag);
      by('pageImage').src = image.src;
      by('pageImage').alt = image.alt;
      by('pageSurface').style.aspectRatio = data.width + ' / ' + data.height;
      by('empty').hidden = true;
      by('pageSurface').hidden = false;
      applyZoom();
      paintMarks();
      by('viewport').scrollTop = scroll * scrollExtent();
      if (found && found.page === page)
        focusWord(found);

      by('ocr').hidden = Boolean(data.words.length) || Boolean(data.ocr);
      by('pageStatus').textContent = data.ocr ? '第 ' + page + ' 页 · 本地识别文本，请对照原页' :
          data.words.length                   ? '第 ' + page + ' 页 · 拖选文字可批注或送入圆桌' :
                                                '第 ' + page + ' 页 · 此页没有可选择的文本层';
      const u = new URL(location.href);
      u.searchParams.set('page', String(page));
      if (!restore) {
        for (const param of ['annotation', 'fingerprint', 'quote', 'start', 'end', 'ocr'])
          u.searchParams.delete(param);
      }
      if (window.SciStationNav?.commitURL)
        window.SciStationNav.commitURL(u, 'replace');
      else
        history.replaceState(null, '', u);
      if (!restore)
        rememberPosition(true);
    } catch (err) {
      if (ticket !== requestNumber)
        return;
      by('pageStatus').textContent = '';
      displayEmpty(errorText(err), true);
    }
  }
  function scrollToBox(box) {
    if (box)
      by('viewport').scrollTop = Math.max(0, box.y * by('pageSurface').clientHeight - 100);
  }
  function focusWord(range) {
    const word = pageData?.words.find(w => w.start < range.end && w.end > range.start);
    if (word)
      scrollToBox(word.box);
    return Boolean(word);
  }
  function sourceNotice(text) {
    by('sourceNotice').textContent = text;
    by('sourceNotice').hidden = false;
  }
  function quoteRange(quote, start, end, annotation) {
    if (start != null || end != null) {
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) ||
          start < 0 || end <= start || end > pageData.text.length || pageData.text.slice(start, end) !== quote)
        return null;
      return {start, end};
    }
    let at = pageData.text.indexOf(quote);
    if (at < 0)
      return null;
    if (pageData.text.indexOf(quote, at + 1) < 0)
      return {start:at, end:at + quote.length};

    // Older marks have geometry but no exact character range. Locate a
    // repeated quote only when the saved mark favors one displayed occurrence.
    const box = annotation?.rects?.[0];
    if (!box)
      return null;
    const matches = [];
    while (at >= 0) {
      const end = at + quote.length;
      const b = pageData.words.find(w => w.start < end && w.end > at)?.box;
      if (b && b.x < box.x + box.width && b.x + b.width > box.x &&
          b.y < box.y + box.height && b.y + b.height > box.y)
        matches.push({start:at, end});
      at = pageData.text.indexOf(quote, at + 1);
    }
    return matches.length === 1 ? matches[0] : null;
  }
  function showTab(notes) {
    by('annTab').setAttribute('aria-selected', String(!notes));
    by('notesTab').setAttribute('aria-selected', String(notes));
    by('annotPanel').hidden = notes;
    by('notesPanel').hidden = !notes;
    window.SciContextRail?.show('inspector');
  }
  function focusInspector() {
    by(by('notesPanel').hidden ? 'annTab' : 'notesTab').focus();
  }
  function renderAnn() {
    const host = by('annotations');
    host.replaceChildren();
    by('annotationCount').textContent = local('readerAnnotationCount', `${annotations.length} 条`, `${annotations.length} annotations`, annotations.length);
    if (!annotations.length) {
      host.append(node('p', '在原文中拖选文字，即可保存第一条批注。', 'muted'));
      return;
    }
    const observedRevision = paper.revision;
    const items = [...annotations].sort(
        (a, b) => a.page - b.page || String(a.created_at).localeCompare(String(b.created_at)));
    items.forEach(a => {
      const card = node('article', null, 'ann-card');
      card.id = 'annotation-' + a.id;
      const actions = node('div', null, 'ann-actions');
      actions.append(button('第 ' + a.page + ' 页', async () => {
        await goPage(a.page);
        if (currentPage === a.page)
          scrollToBox(a.rects?.[0]);
      }, 'where'));
      actions.append(button('编辑', async () => {
        if (hasAnnotationDraft()) {
          message(text('先保存或取消当前批注草稿。', 'Save or cancel the current annotation draft first.'));
          return;
        }
        await goPage(a.page);
        if (currentPage === a.page && activateSelected(a, true, observedRevision))
          by('comment').focus();
      }));
      if (a.selected_text)
        actions.append(button('入会', () => openHandoff(a)));
      const remove = button('删除', async () => {
        if (remove.dataset.confirm !== 'yes') {
          remove.dataset.confirm = 'yes';
          remove.textContent = text('确认删除', 'Confirm deletion');
          return;
        }
        try {
          await fetchJSON(apiRoot + '/annotations/' + encodeURIComponent(a.id) + '?revision=' + observedRevision, 'DELETE');
        } catch(err) {
          if (err.status!==409) throw err;
          annotationConflict();
          return;
        }
        if (selection?.id === a.id && !hasAnnotationDraft())
          resetSelection();
        await refreshRevision();
      });
      actions.append(remove);
      card.append(actions);
      if (a.selected_text)
        card.append(node('blockquote', a.selected_text));
      else if (a.rects?.length)
        card.append(node('p', '原文区域', 'muted'));
      if (a.note)
        card.append(node('p', a.note));
      host.append(card);
    });
  }
  function annotationConflict() {
    by('reloadAnnotations').hidden=false;
    message('批注已有更新。读取最新批注时会保留当前草稿。');
  }
  function applyPaperSnapshot(updated, {replaceNote = false} = {}) {
    if (updated.revision < paper.revision)
      updated = paper;
    const updatedNotes = updated.notes || '';
    // Advance the base of an unrelated draft only if its saved content is unchanged.
    if (updatedNotes === savedNote)
      noteRevision = updated.revision;
    if (!editingNote || replaceNote) {
      savedNote = updatedNotes;
      by('notes').value = savedNote;
      noteRevision = updated.revision;
    }
    const latestAnnotations = updated.annotations || [];
    if (editingAnnotation) {
      const latest = latestAnnotations.find(a => a.id === editingAnnotation.id);
      if (latest && JSON.stringify(latest) === JSON.stringify(selection))
        editingAnnotation.revision = updated.revision;
    }
    paper = updated;
    annotations = latestAnnotations;
    renderAnn();
    paintMarks();
  }
  async function refreshRevision() {
    applyPaperSnapshot(await fetchJSON(apiRoot));
    by('reloadAnnotations').hidden = true;
  }
  async function saveAnnotation() {
    if (!selection || by('saveSelection').disabled)
      return;
    const saving = selection, edit = editingAnnotation;
    const payload = {
      page: selection.page,
      kind: by('kind').value,
      selected_text: selection.selected_text,
      note: by('comment').value.trim(),
      color: selection.color || '#edc947',
      rects: selection.rects,
      selectionStart: selection.selectionStart,
      selectionEnd: selection.selectionEnd,
      ocr: selection.ocr
    };
    for (const id of ['saveSelection', 'comment', 'kind'])
      by(id).disabled = true;
    try {
      await fetchJSON(
          apiRoot + '/annotations' + (edit ? '/' + encodeURIComponent(edit.id) + '?revision=' + edit.revision : ''), edit ? 'PUT' : 'POST',
          payload);
      if (selection === saving) {
        resetSelection();
        window.getSelection()?.removeAllRanges();
      }
      await refreshRevision();
      message('已保存批注。');
    } catch (e) {
      if(e.status===409) annotationConflict();
      else message(errorText(e));
    } finally {
      for (const id of ['saveSelection', 'comment', 'kind'])
        by(id).disabled = false;
    }
  }
  async function saveNote() {
    if (!paper || !editingNote || savingNote)
      return;
    const draft = by('notes').value;
    savingNote = true;
    by('saveNotes').disabled = true;
    try {
      const fresh = await fetchJSON(apiRoot, 'PUT', {revision: noteRevision, notes: draft});
      savedNote = draft;
      noteRevision = fresh.revision;
      editingNote = by('notes').value !== draft;
      applyPaperSnapshot(fresh);
      by('notesStatus').textContent = editingNote ? text('有未保存的更改', 'Unsaved changes') : text('已保存', 'Saved');
      by('reloadNote').hidden = true;
    } catch (e) {
      by('notesStatus').textContent = e.status === 409 ?
          '已有较新的保存版本。当前草稿仍在编辑器中，可复制草稿后重新读取。' :
          errorText(e);
      by('reloadNote').hidden = e.status !== 409;
    } finally {
      savingNote = false;
      by('saveNotes').disabled = !editingNote;
    }
  }
  function updateMeetings() {
    const p = projects.find(x => x.id === by('projectSelect').value), el = by('sessionSelect');
    el.replaceChildren(new Option('新建圆桌', ''));
    if (p)
      sessions.filter(s => s.project_id === p.id && s.status !== 'closed')
          .forEach(s => el.append(new Option(s.title || s.topic || text('已有圆桌', 'Existing Roundtable'), s.id)));
    by('submitHandoff').disabled = !p;
  }
  let handoffSelection = null;
  async function openHandoff(a) {
    if (!a?.selected_text)
      return;
    if (Array.from(a.selected_text).length > 2800) {
      message('一条会议摘录最多 2,800 字符，请缩小选段。');
      return;
    }
    const result =
        await Promise.all([fetchJSON('/api/research/projects'), fetchJSON('/api/studio/sessions')]);
    projects = result[0].filter(p => paper.project_ids?.includes(p.id));
    sessions = Array.isArray(result[1]) ? result[1] : result[1].sessions || [];
    if (!projects.length) {
      message('请先在文献库中将论文加入一个科研项目。');
      return;
    }
    const allowed = await Promise.all(projects.map(async project => {
      try {
        const modules = await window.SciStationModules.load(project.id);
        return window.SciStationModules.isEnabled(modules, "ai-lab");
      } catch { return false; }
    }));
    projects = projects.filter((_, index) => allowed[index]);
    if (!projects.length) {
      message(text("此论文的项目均未启用 AI。", "AI is unavailable for this paper’s projects."));
      return;
    }
    handoffSelection = a;
    by('handoffQuote').textContent = a.selected_text;
    const select = by('projectSelect');
    select.replaceChildren();
    projects.forEach(p => select.append(new Option(p.name, p.id)));
    const intended = [projectID, ...(paper.project_ids || [])].find(id => projects.some(p => p.id === id));
    if (intended)
      select.value = intended;
    updateMeetings();
    by('handoffDialog').showModal();
  }
  function verifyExcerpt(source) {
    return fetchJSON(apiRoot + '/verify-evidence', 'POST', {
      page: source.page,
      quote: source.quote,
      sourceHash: source.fingerprint,
      annotationId: source.annotationId,
      selectionStart: source.selectionStart,
      selectionEnd: source.selectionEnd,
      ocr: source.ocr
    });
  }
  async function submitHandoff() {
    const submit = by('submitHandoff');
    if (!handoffSelection || !by('projectSelect').value || submit.disabled)
      return;
    const projectId = by('projectSelect').value, sessionId = by('sessionSelect').value;
    const payload = {
      projectId,
      paperId: paper.id,
      title: paper.title,
      page: handoffSelection.page,
      quote: handoffSelection.selected_text,
      fingerprint: paper.file_sha256 || '',
      annotationId: handoffSelection.id || '',
      selectionStart: handoffSelection.selectionStart,
      selectionEnd: handoffSelection.selectionEnd,
      ocr: handoffSelection.ocr || undefined,
      sessionId
    };
    const dialog = by('handoffDialog');
    submit.disabled = true;
    try {
      await verifyExcerpt(payload);
      if (!dialog.open || by('projectSelect').value !== projectId || by('sessionSelect').value !== sessionId)
        return;
      sessionStorage.setItem('sci-station.paper-handoff', JSON.stringify(payload));
      const path = new URL('/studio', location.origin);
      path.searchParams.set('project', projectId);
      if (sessionId)
        path.searchParams.set('session', sessionId);
      location.assign(path);
    } catch (e) {
      dialog.close();
      message(errorText(e));
    } finally {
      submit.disabled = !by('projectSelect').value;
    }
  }
  function showFind(open) {
    by('findBar').hidden = !open;
    by('findButton').setAttribute('aria-expanded', String(open));
    if (open) {
      by('findTerm').focus();
      by('findTerm').select();
    } else {
      ++searchNumber;
      found = null;
      paintMarks();
    }
  }
  async function findText(e, direction = 1) {
    e?.preventDefault();
    const query = by('findTerm').value.trim();
    if (!query)
      return;
    const n = ++searchNumber, host = by('findResults');
    host.textContent = text('正在查找…', 'Searching…');
    try {
      const data = await fetchJSON(apiRoot + '/pages/search?q=' + encodeURIComponent(query));
      if (n !== searchNumber)
        return;
      // Include pages that the reader has explicitly recognized offline.
      for (const [page, local] of recognized) {
        if (data.items.some(x => x.page === page))
          continue;
        const text = local.text.toLocaleLowerCase(), term = query.toLocaleLowerCase();
        let at = 0;
        while ((at = text.indexOf(term, at)) !== -1) {
          if (data.items.length >= 120) {
            data.limited = true;
            break;
          }
          data.items.push({
            page,
            start: at,
            end: at + term.length,
            text: local.text.slice(Math.max(0, at - 30), at + term.length + 40)
          });
          at += term.length;
        }
      }
      data.items.sort((a, b) => a.page - b.page || a.start - b.start);
      searchResults = data.items;
      searchedTerm = query;
      focusedResult = -1;
      host.replaceChildren(node(
          'p',
          data.items.length ? (data.limited ? '显示前 120 处匹配' : '共 ' + data.items.length + ' 处匹配') :
                              '未找到匹配文字',
          'muted'));
      data.items.forEach((hit, i) => host.append(button('第 ' + hit.page + ' 页 · ' + hit.text,
          () => focusResult(i))));
      if (data.items.length)
        await focusResult(direction === 1 ? 0 : data.items.length - 1);
      else {
        found = null;
        paintMarks();
      }
    } catch (err) {
      if (n === searchNumber)
        host.textContent = errorText(err);
    }
  }
  function focusResult(index) {
    focusedResult = index;
    found = searchResults[index];
    return goPage(found.page);
  }
  function advanceFind(direction) {
    if (by('findBar').hidden)
      showFind(true);
    if (!by('findTerm').value.trim())
      return;
    if (by('findTerm').value.trim() !== searchedTerm || !searchResults.length)
      return findText(null, direction);
    const offset = focusedResult < 0 && direction === -1 ? 0 : focusedResult;
    return focusResult((offset + direction + searchResults.length) % searchResults.length);
  }
  async function restoreReaderPosition() {
    const fingerprint = inputs.get('fingerprint');
    const annotationId = inputs.get('annotation');
    const quoteParam = inputs.get('quote');
    const isCitation = Boolean(fingerprint || annotationId || quoteParam);
    const annot = annotations.find(a => a.id === annotationId);
    const saved = paper.reading_position?.sourceHash === paper.file_sha256 ? paper.reading_position : null;
    zoom = Math.max(.55, Math.min(3, Number(saved?.zoom) || 1));
    const requested = Number(inputs.get('page')) || annot?.page || saved?.page || 1;
    const sourceAnn = annot?.page === requested && (!quoteParam || quoteParam === annot.selected_text) ? annot : null;
    const source = {
      page: requested,
      quote: quoteParam || sourceAnn?.selected_text,
      annotationId,
      fingerprint,
      selectionStart: inputs.has('start') ? Number(inputs.get('start')) : sourceAnn?.selectionStart,
      selectionEnd: inputs.has('end') ? Number(inputs.get('end')) : sourceAnn?.selectionEnd,
      ocr: inputs.get('ocr') === '1' || (!quoteParam && sourceAnn?.ocr)
    };
    if (fingerprint && fingerprint !== paper.file_sha256) {
      sourceNotice('当前 PDF 与摘录保存的原件指纹不同。');
      await goPage(1, {restore:true, track:false});
      return;
    }
    if (source.quote && (fingerprint || quoteParam)) {
      try {
        await verifyExcerpt(source);
      } catch (e) {
        sourceNotice('无法核对保存的 PDF 摘录。' + errorText(e));
        await goPage(e.status === 409 ? 1 : requested, {restore:true, track:false});
        return;
      }
    }
    await goPage(requested, {
      restore:true,
      track:!isCitation,
      scroll:!isCitation && saved?.page === requested ? Number(saved.scroll) || 0 : 0,
      ocr:Boolean(source.ocr)
    });
    if (!isCitation || !pageData || currentPage !== requested)
      return;
    if (source.quote) {
      const range = quoteRange(source.quote, source.selectionStart, source.selectionEnd, sourceAnn);
      if (range && focusWord(range)) {
        found = {page:requested, ...range};
        paintMarks();
      } else {
        sourceNotice('已打开原页，但无法定位所保存的选段。');
      }
    } else if (sourceAnn) {
      scrollToBox(sourceAnn.rects?.[0]);
    }
    if (sourceAnn)
      document.getElementById('annotation-' + sourceAnn.id)?.scrollIntoView({block:'nearest'});
  }
  async function initialize() {
    if (window.SciStationI18n) await window.SciStationI18n.ready;
    updatePageControls();
    by('home').href = '/research?view=papers' + (projectID ? '&project=' + encodeURIComponent(projectID) : '');
    by('title').textContent = local('routePDFReader', 'PDF 阅读器', 'PDF Reader');
    by('empty').textContent = local('readerOpening', '正在打开论文…', 'Opening paper…');
    if (!paperID) {
      displayEmpty(text('未选择论文，请从科研工作区打开。', 'Open a paper from the research workspace.'));
      return;
    }
    try {
      paper = await fetchJSON(apiRoot);
      document.title = paper.title + ' · Sci-Station';
      by('title').textContent = paper.title;
      by('byline').textContent = [
        (paper.authors || []).join('、'), paper.year || '', paper.doi || paper.arxiv || ''
      ].filter(Boolean).join(' · ');
      by('bib').href = apiRoot + '/bibtex';
      by('bib').hidden = false;
      savedNote = paper.notes || '';
      noteRevision = paper.revision;
      by('notes').value = savedNote;
      window.SciReaderGraphSource?.open(paper, inputs, by, showTab);
      annotations = paper.annotations || [];
      renderAnn();
      if (!paper.has_pdf) {
        if (inputs.has('fingerprint'))
          sourceNotice('此论文当前缺少摘录所引用的 PDF 原件。');
        displayEmpty(text('此条文献暂未附有本地 PDF。', 'This paper has no local PDF.'));
        const controls = node('div', null, 'actions');
        const file = node('input');
        file.type = 'file';
        file.accept = 'application/pdf,.pdf';
        file.hidden = true;
        const attach = button('上传本地 PDF', () => file.click());
        const remote = button('获取在线 PDF', () => attachPDF(null));
        async function attachPDF(blob) {
          attach.disabled = remote.disabled = true;
          try {
            if (blob) {
              const data = new FormData();
              data.append('file', blob);
              const res =
                  await fetch(apiRoot + '/pdf', {method: 'POST', headers: {'X-Roundtable': '1'}, body: data});
              if (!res.ok) {
                let e;
                try {
                  e = await res.json();
                } catch {
                }
                throw new Error(e?.error || '上传 PDF 失败');
              }
            } else
              await fetchJSON(apiRoot + '/pdf', 'POST', {});
            location.reload();
          } catch (err) {
            message(errorText(err));
          } finally {
            attach.disabled = remote.disabled = false;
          }
        }
        file.onchange = () => {
          if (file.files[0])
            attachPDF(file.files[0]);
        };
        controls.append(file, attach);
        if (paper.url || paper.doi || paper.arxiv)
          controls.append(remote);
        by('empty').append(controls);
        if (paper.url && /^https?:\/\//i.test(paper.url)) {
          const u = node('a', '打开文献来源 ↗');
          u.href = paper.url;
          u.target = '_blank';
          u.rel = 'noopener';
          by('empty').append(u);
        }
        return;
      }
      by('exportMarkdown').href = apiRoot + '/markdown';
      by('exportMarkdown').hidden = false;
      by('original').href = apiRoot + '/pdf';
      by('original').hidden = false;
      const info = await fetchJSON(apiRoot + '/pages');
      pageCount = info.pages;
      nativeAvailable = true;
      await restoreReaderPosition();
    } catch (err) {
      displayEmpty(errorText(err), Boolean(paper?.has_pdf));
    }
  }
  by('prev').onclick = () => goPage(currentPage - 1);
  by('next').onclick = () => goPage(currentPage + 1);
  by('pageNo').onchange = () => goPage(Number(by('pageNo').value));
  by('larger').onclick = () => {
    zoom = Math.min(3, zoom + .2);
    applyZoom();
    trackedPosition = true;
    rememberPosition(true);
  };
  by('smaller').onclick = () => {
    zoom = Math.max(.55, zoom - .2);
    applyZoom();
    trackedPosition = true;
    rememberPosition(true);
  };
  by('fit').onclick = () => {
    zoom = 1;
    applyZoom();
    trackedPosition = true;
    rememberPosition(true);
  };
  by('findButton').onclick = () => showFind(by('findBar').hidden);
  by('closeFind').onclick = () => showFind(false);
  by('searchForm').onsubmit = findText;
  by('reader-inspect').onclick = event => {
    window.SciContextRail?.toggle('inspector', event?.currentTarget || by('reader-inspect'));
    if (!by('reader-inspector').hidden) focusInspector();
  };
  by('reader-close').onclick = () => window.SciContextRail?.close();
  by('reader-pin').onclick = () => window.SciContextRail?.pin();
  by('annTab').onclick = () => showTab(false);
  by('notesTab').onclick = () => showTab(true);
  by('notes').oninput = () => {
    editingNote = by('notes').value !== savedNote;
    by('saveNotes').disabled = !editingNote || savingNote;
    by('notesStatus').textContent = editingNote ? text('有未保存的更改', 'Unsaved changes') : '';
  };
  by('reloadAnnotations').onclick = async () => {
    try {
      await refreshRevision();
      message('已读取最新批注。');
    } catch (err) {
      message(errorText(err));
    }
  };
  by('saveNotes').onclick = saveNote;
  by('reloadNote').onclick = async () => {
    try {
      applyPaperSnapshot(await fetchJSON(apiRoot), {replaceNote:true});
      editingNote = false;
      by('saveNotes').disabled = true;
      by('notesStatus').textContent = text('已读取保存版本。', 'Saved version loaded.');
      by('reloadNote').hidden = true;
    } catch (e) {
      message(errorText(e));
    }
  };

  let regionMode = false, drag = null;
  function setRegionMode(on) {
    regionMode = on;
    by('regionButton').setAttribute('aria-pressed', String(on));
    by('pageSurface').classList.toggle('region-mode', on);
    if (!on && drag) {
      drag.el.remove();
      drag = null;
    }
  }
  function relativePoint(e) {
    const bounds = by('pageSurface').getBoundingClientRect();
    const clip = n => Math.max(0, Math.min(1, n));
    return {
      x: clip((e.clientX - bounds.left) / bounds.width),
      y: clip((e.clientY - bounds.top) / bounds.height)
    };
  }
  function boxBetween(a, b) {
    return {
      x: Math.min(a.x, b.x),
      y: Math.min(a.y, b.y),
      width: Math.abs(a.x - b.x),
      height: Math.abs(a.y - b.y)
    };
  }
  by('regionButton').onclick = () => setRegionMode(!regionMode);
  by('pageSurface').addEventListener('pointerdown', e => {
    if (!regionMode || !pageData || e.button !== 0)
      return;
    e.preventDefault();
    const el = node('span', null, 'region-draft');
    by('pageSurface').append(el);
    const point = relativePoint(e);
    drag = {point, el, pointer: e.pointerId};
    by('pageSurface').setPointerCapture(e.pointerId);
    place(el, boxBetween(point, point));
  });
  by('pageSurface').addEventListener('pointermove', e => {
    if (drag && drag.pointer === e.pointerId)
      place(drag.el, boxBetween(drag.point, relativePoint(e)));
  });
  by('pageSurface').addEventListener('pointerup', e => {
    if (!drag || drag.pointer !== e.pointerId)
      return;
    const rect = boxBetween(drag.point, relativePoint(e));
    by('pageSurface').releasePointerCapture(e.pointerId);
    setRegionMode(false);
    if (rect.width < .002 || rect.height < .002)
      return;
    showTab(false);
    if (activateSelected({page: currentPage, selected_text: '', kind: 'note', rects: [rect], note: ''}))
      by('comment').focus();
  });
  by('pageSurface').addEventListener('pointercancel', () => setRegionMode(false));

  by('ocr').onclick = async () => {
    const target = currentPage;
    by('ocr').disabled = true;
    by('pageStatus').textContent = '正在本机识别页面文字…';
    try {
      const data = await fetchJSON(apiRoot + '/pages/' + target + '/ocr');
      recognized.set(target, data);
      if (target === currentPage) {
        await goPage(target);
        if (!data.words.length)
          by('pageStatus').textContent = '本页未识别到文字。';
      }
    } catch (e) {
      if (target === currentPage)
        by('pageStatus').textContent = errorText(e);
    } finally {
      by('ocr').disabled = false;
    }
  };
  by('textLayer').addEventListener('pointerup', () => setTimeout(collectSelection, 0));
  by('textLayer').addEventListener('keyup', collectSelection);
  by('addHighlight').onclick = () => {
    showTab(false);
    by('comment').focus();
  };
  by('saveSelection').onclick = saveAnnotation;
  by('clearSelection').onclick = () => {
    resetSelection();
    window.getSelection()?.removeAllRanges();
  };
  by('handoff').onclick = () => openHandoff(selection).catch(e => message(errorText(e)));
  by('projectSelect').onchange = updateMeetings;
  by('cancelHandoff').onclick = () => by('handoffDialog').close();
  by('submitHandoff').onclick = submitHandoff;
  window.addEventListener('resize', applyZoom);
  window.addEventListener('sci:language', () => {
    updateSelectionLabels();
    applyZoom();
  });
  const viewport = by('viewport');
  if (typeof ResizeObserver !== 'undefined') new ResizeObserver(applyZoom).observe(viewport);
  viewport.addEventListener('scroll', () => rememberPosition());
  for (const event of ['wheel', 'pointerdown', 'keydown'])
    viewport.addEventListener(event, () => trackedPosition = true);
  window.addEventListener('pagehide', flushPosition);
  window.addEventListener('beforeunload', e => {
    void flushPosition();
    if (editingNote || hasAnnotationDraft()) {
      e.preventDefault();
      e.returnValue = '';
    }
  });
  window.addEventListener('scistation:command', e => {
    const command = e.detail;
    if (command === 'find' && nativeAvailable)
      showFind(true);
    else if (command === 'findNext' && nativeAvailable)
      void advanceFind(1);
    else if (command === 'findPrevious' && nativeAvailable)
      void advanceFind(-1);
    else if (command === 'save' && !by('notesPanel').hidden && !by('saveNotes').disabled)
      void saveNote();
    else if (command === 'save' && !by('annotPanel').hidden && selection)
      void saveAnnotation();
    else if (command === 'inspector') {
      window.SciContextRail?.show('inspector');
      focusInspector();
    } else if (command === 'bibtex' && !by('bib').hidden)
      by('bib').click();
    else if ((command === 'externalPDF' || command === 'reveal') && paper?.has_pdf) {
      const action = command === 'reveal' ? 'reveal' : 'open';
      void fetchJSON(apiRoot + '/native-file', 'POST', {action}).catch(e => message(errorText(e)));
    } else
      return;
    e.preventDefault();
  });
  initialize();
})();
