const API = {
  session: null,
  ws: null,
  compressing: false,
  files: [],
  previewFileId: null,
  previewDebounce: null,
  objectUrls: new Map(),
  lastPreviewUrl: null,
};

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

const VIDEO_EXTS = new Set(["mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv"]);
const IMAGE_EXTS = new Set(["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif"]);

async function init() {
  const res = await fetch("/api/session", { method: "POST" });
  const data = await res.json();
  API.session = data.session_id;
  $("#sessionBadge").textContent = `Session ${API.session}`;
  connectWS();
  bindEvents();
  saveSettings();
  updateAllMetrics();
}

function toast(msg, type = "info") {
  const el = document.createElement("div");
  el.className = `toast ${type}`;
  el.textContent = msg;
  $("#toastContainer").appendChild(el);
  setTimeout(() => el.remove(), 3400);
}

function connectWS() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const url = `${proto}//${location.host}/api/session/${API.session}/ws`;
  API.ws = new WebSocket(url);
  API.ws.onmessage = (e) => {
    try {
      handleWSMessage(JSON.parse(e.data));
    } catch {}
  };
  API.ws.onclose = () => {
    if (!API.compressing && API.session) setTimeout(connectWS, 2000);
  };
}

function handleWSMessage(msg) {
  switch (msg.type) {
    case "file_status":
      updateFileStatus(msg.file_id, msg.status, msg.output_size, msg.detail);
      break;
    case "batch_stats":
      updateBatchStats(msg.completed, msg.total, msg.files_per_sec, msg.eta_secs, msg.total_source, msg.total_output, msg.savings_pct);
      break;
    case "batch_start":
      onBatchStart(msg.total);
      break;
    case "batch_complete":
      onBatchComplete(msg.summary, msg.total_source, msg.total_output, msg.savings_pct);
      break;
    case "log":
      appendLog(msg.line);
      break;
  }
}

async function addFilesToQueue(fileList) {
  const files = [...fileList];
  const formData = new FormData();
  for (const f of files) formData.append("files", f);

  try {
    const res = await fetch(`/api/session/${API.session}/upload`, { method: "POST", body: formData });
    const data = await res.json();
    if (data.error) return toast(data.error, "error");

    data.files.forEach((file, index) => {
      const source = files[index];
      const ext = extensionOf(file.filename);
      if (source && IMAGE_EXTS.has(ext)) {
        API.objectUrls.set(file.file_id, URL.createObjectURL(source));
      }
      API.files.push({ ...file, status: file.status || "queued" });
    });

    renderQueue();
    updateCompressBtn();
    updateAllMetrics();
    updateSmartHint();
    toast(`${data.files.length} file${data.files.length === 1 ? "" : "s"} added`, "success");
  } catch {
    toast("Upload failed", "error");
  }
}

function renderQueue() {
  const list = $("#queueList");
  const empty = $("#queueEmpty");
  const table = $("#queueTable");

  if (API.files.length === 0) {
    empty.hidden = false;
    table.hidden = true;
    $("#fileCount").textContent = "0 files";
    $("#clearFilesBtn").disabled = true;
    $("#queueSubtitle").textContent = "Add files to see thumbnails, savings estimates, and live progress.";
    updateTimeline();
    return;
  }

  empty.hidden = true;
  table.hidden = false;
  $("#fileCount").textContent = `${API.files.length} file${API.files.length === 1 ? "" : "s"}`;
  $("#clearFilesBtn").disabled = false;
  $("#queueSubtitle").textContent = "Live states, estimated savings, and previews stay attached to each file.";

  list.innerHTML = API.files.map((f, index) => queueRowTemplate(f, index)).join("");
  loadThumbnails();
  updateTimeline();
}

function queueRowTemplate(f, index) {
  const statusClass = normalizeStatus(f.status || "queued");
  const ext = extensionOf(f.filename);
  const original = f.source_size || 0;
  const estimated = f.output_size || estimatedOutputSize(original);
  const savedPct = savingPercent(original, estimated);
  const statusLabel = labelForStatus(statusClass);
  const progressPct = statusClass === "processing" ? 62 : terminalStatus(statusClass) ? 100 : 0;
  const selected = API.previewFileId === f.file_id ? " selected" : "";
  const download = terminalStatus(statusClass) && f.file_id
    ? `<a class="download-link" data-file-id="${f.file_id}" onclick="event.stopPropagation();downloadFile('${f.file_id}')">download</a>`
    : "";

  return `<div class="queue-item ${statusClass}${selected}" style="animation-delay:${Math.min(index * 30, 240)}ms" data-file-id="${f.file_id}" data-file-ext="${ext}" onclick="selectPreview('${f.file_id}')">
    <div class="queue-icon" data-file-id="${f.file_id}">${fileIcon(ext)}</div>
    <div class="queue-info">
      <div class="queue-name">${escapeHtml(f.filename)}</div>
      <div class="queue-meta">${ext.toUpperCase() || "FILE"} | ${humanSize(original)} -> ${humanSize(estimated)}</div>
      <div class="queue-estimate">${savedPct}% saved ${f.detail ? "| " + escapeHtml(f.detail) : ""}</div>
    </div>
    <div class="queue-status ${statusClass}">${statusLabel}${download}</div>
    <div class="queue-progress"><div class="queue-progress-bar ${statusClass}" style="width:${progressPct}%"></div></div>
  </div>`;
}

function fileIcon(ext) {
  if (VIDEO_EXTS.has(ext)) {
    return `<svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.55"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>`;
  }
  return `<svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.55"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8.5" r="1.5"/><path d="M21 15l-5-5L6 21"/></svg>`;
}

function loadThumbnails() {
  $$(".queue-icon[data-file-id]").forEach((el) => {
    if (el.querySelector("img")) return;
    const fileId = el.dataset.fileId;
    const item = el.closest(".queue-item");
    const ext = item?.dataset.fileExt || "";
    if (!IMAGE_EXTS.has(ext)) return;

    const img = new Image();
    img.alt = "";
    img.onload = () => {
      el.innerHTML = "";
      el.appendChild(img);
    };
    img.onerror = () => {};
    img.src = API.objectUrls.get(fileId) || `/api/session/${API.session}/raw/${fileId}`;
  });
}

function updateFileStatus(fileId, status, outputSize, detail) {
  const f = API.files.find((x) => x.file_id === fileId);
  if (!f) return;
  f.status = status;
  f.output_size = outputSize;
  f.detail = detail;
  renderQueue();
  updateAllMetrics();
  if (API.previewFileId === fileId) selectPreview(fileId, { preserveQuality: true });
}

function updateCompressBtn() {
  $("#compressBtn").disabled = API.files.length === 0 || API.compressing;
}

function updateBatchStats(completed, total, rate, eta, totalSource, totalOutput, savingsPct) {
  $("#batchProgressCard").hidden = false;
  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;
  $("#batchProgressFill").style.width = `${Math.min(pct, 100)}%`;
  $("#batchCount").textContent = `${completed} / ${total} done`;
  $("#batchRate").textContent = `${rate} files/s`;
  $("#batchETA").textContent = eta > 0 ? `ETA ${Math.round(eta)}s` : "ETA -";
  $("#progressCaption").textContent = rate ? `Processing at ${rate} files per second.` : "Processing queue.";
  $("#filesProcessedMetric").textContent = `${completed} / ${total}`;
  $("#etaMetric").textContent = eta > 0 ? `${Math.round(eta)}s` : "Done";

  const savingsEl = $("#batchSavings");
  if (totalSource && totalOutput !== undefined) {
    savingsEl.textContent = `${humanSize(totalSource)} -> ${humanSize(totalOutput)} (${savingsPct}% saved)`;
    savingsEl.hidden = false;
    $("#totalSavedMetric").textContent = humanSize(Math.max(totalSource - totalOutput, 0));
    $("#compressionRatioMetric").textContent = `${Math.max(0, Math.round(savingsPct || 0))}%`;
  }
  updateTimeline();
}

function onBatchStart(total) {
  API.compressing = true;
  $("#filesProcessedMetric").textContent = `0 / ${total}`;
  $("#etaMetric").textContent = "Calculating";
  updateTimeline();
}

function onBatchComplete(summary, totalSource, totalOutput, savingsPct) {
  API.compressing = false;
  $("#compressBtn").innerHTML = `<span aria-hidden="true">▶</span> Compress Queue`;
  $("#stopBtn").disabled = true;
  updateCompressBtn();

  if (totalSource && totalOutput !== undefined) {
    const saved = totalSource - totalOutput;
    summary += ` | ${humanSize(totalSource)} -> ${humanSize(totalOutput)} (${savingsPct}% saved)`;
    $("#totalSavedMetric").textContent = humanSize(Math.max(saved, 0));
    $("#compressionRatioMetric").textContent = `${Math.max(0, Math.round(savingsPct || 0))}%`;
  }
  $("#etaMetric").textContent = "Done";
  appendLog(summary);
  toast(summary, summary.toLowerCase().includes("error") ? "error" : "success");
  $("#downloadAllBtn").disabled = !API.files.some((f) => terminalStatus(normalizeStatus(f.status)));
  updateTimeline();
}

function updateTimeline() {
  const timeline = $("#timeline");
  if (!timeline) return;
  timeline.style.setProperty("--segments", Math.max(API.files.length, 1));
  timeline.innerHTML = API.files.map((f) => `<span class="${normalizeStatus(f.status || "queued")}"></span>`).join("");
}

function appendLog(line) {
  const area = $("#logArea");
  const empty = area.querySelector(".log-empty");
  if (empty) empty.remove();

  const el = document.createElement("div");
  el.className = "log-line info";
  const fileTagMatch = line.match(/^\[([a-z0-9_]+)\]/i);
  if (fileTagMatch) {
    el.innerHTML = `<span class="file-tag">[${fileTagMatch[1]}]</span>${escapeHtml(line.slice(fileTagMatch[0].length))}`;
  } else {
    el.textContent = line;
  }
  if (line.includes("[ERROR]")) el.className = "log-line error";
  else if (line.includes("[BEST EFFORT]")) el.className = "log-line warning";

  area.appendChild(el);
  area.scrollTop = area.scrollHeight;
}

function selectPreview(fileId, options = {}) {
  API.previewFileId = fileId;
  renderQueue();
  const f = API.files.find((x) => x.file_id === fileId);
  if (!f) return;

  const ext = extensionOf(f.filename);
  $("#zoomPreviewBtn").disabled = !IMAGE_EXTS.has(ext);
  $("#previewHint").textContent = `${f.filename} | ${humanSize(f.source_size)} original`;

  if (!IMAGE_EXTS.has(ext)) {
    $("#previewArea").innerHTML = `<p class="preview-placeholder">Video preview is not available here, but compression metrics will update live.</p>`;
    $("#previewSliderRow").hidden = true;
    $("#previewQualityRow").hidden = true;
    return;
  }

  const quality = options.preserveQuality ? $("#previewQuality").value : 80;
  $("#previewQuality").value = quality;
  $("#previewQualityLabel").textContent = quality;
  $("#compareSlider").value = 56;
  $("#compareLabel").textContent = "56%";
  $("#previewSliderRow").hidden = false;
  $("#previewQualityRow").hidden = false;
  $("#previewArea").classList.add("preview-loading");
  renderComparePreview(f, API.objectUrls.get(fileId) || `/api/session/${API.session}/raw/${fileId}`, null);
  loadPreview();
}

function renderComparePreview(file, originalSrc, compressedSrc) {
  const originalSize = humanSize(file.source_size || 0);
  const compressedSize = file.output_size ? humanSize(file.output_size) : "Rendering";
  const saved = file.output_size ? `${savingPercent(file.source_size, file.output_size)}% saved` : `${savingPercent(file.source_size, estimatedOutputSize(file.source_size))}% estimated`;
  $("#previewArea").innerHTML = `<div class="compare-wrap">
    <img class="compare-before" src="${originalSrc}" alt="Original preview">
    <img class="compare-after" id="compareAfterImage" src="${compressedSrc || originalSrc}" alt="Compressed preview">
    <div class="compare-handle" id="compareHandle"></div>
    <div class="preview-overlay">
      <div class="preview-chip"><strong>Original</strong><span>${originalSize}</span></div>
      <div class="preview-chip"><strong>Compressed</strong><span id="previewCompressed">${compressedSize} · ${saved}</span></div>
    </div>
  </div>`;
  updateCompareReveal();
}

function loadPreview() {
  if (!API.previewFileId) return;
  const f = API.files.find((x) => x.file_id === API.previewFileId);
  if (!f) return;

  const quality = parseInt($("#previewQuality").value, 10);
  const formData = new FormData();

  fetch(`/api/session/${API.session}/raw/${API.previewFileId}`)
    .then((r) => r.blob())
    .then((blob) => {
      formData.append("file", blob, f.filename);
      formData.append("max_size", getTargetSize());
      formData.append("quality", quality);
      return fetch("/api/preview", { method: "POST", body: formData });
    })
    .then((r) => r.blob().then((blob) => ({ blob, headers: r.headers })))
    .then(({ blob, headers }) => {
      if (API.lastPreviewUrl) URL.revokeObjectURL(API.lastPreviewUrl);
      API.lastPreviewUrl = URL.createObjectURL(blob);
      const img = $("#compareAfterImage");
      if (img) img.src = API.lastPreviewUrl;
      const compressed = headers.get("X-Output-Size");
      if (compressed) {
        const size = parseInt(compressed, 10);
        const f = API.files.find((x) => x.file_id === API.previewFileId);
        if (f) $("#previewCompressed").textContent = `${humanSize(size)} · ${savingPercent(f.source_size, size)}% saved`;
      }
      $("#previewArea").classList.remove("preview-loading");
    })
    .catch(() => $("#previewArea").classList.remove("preview-loading"));
}

function updateCompareReveal() {
  const value = $("#compareSlider")?.value || 56;
  $("#compareLabel").textContent = `${value}%`;
  const after = $("#compareAfterImage");
  const handle = $("#compareHandle");
  if (after) after.style.clipPath = `inset(0 0 0 ${value}%)`;
  if (handle) handle.style.left = `${value}%`;
}

function downloadFile(fileId) {
  window.open(`/api/session/${API.session}/download/${fileId}`, "_blank");
}

function downloadAll() {
  window.open(`/api/session/${API.session}/download-all`, "_blank");
}

function getTargetSize() {
  const active = document.querySelector(".preset.active");
  if (active && active.dataset.value) return active.dataset.value;
  const val = $("#customSizeInput").value.trim();
  const unit = $("#customSizeUnit").value;
  if (val) return val + unit;
  return "500kb";
}

function getSettings() {
  return {
    max_size: getTargetSize(),
    output_format: $("#outputFormat").value,
    name_mode: $("#nameMode").value,
    min_quality: parseInt($("#minQuality").value, 10),
    max_quality: parseInt($("#maxQuality").value, 10),
    min_side: parseInt($("#minSide").value, 10),
    keep_metadata: $("#keepMetadata").checked,
  };
}

function saveSettings() {
  if (!API.session || API.compressing) return;
  fetch(`/api/session/${API.session}/settings`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(getSettings()),
  }).catch(() => {});
  updateAllMetrics();
  updateSmartHint();
  if (API.previewFileId) {
    clearTimeout(API.previewDebounce);
    API.previewDebounce = setTimeout(loadPreview, 240);
  }
}

async function startCompression() {
  if (API.compressing || API.files.length === 0) return;

  API.compressing = true;
  API.files.forEach((file) => {
    file.status = "queued";
    file.output_size = null;
    file.detail = null;
  });
  renderQueue();
  $("#compressBtn").disabled = true;
  $("#compressBtn").innerHTML = `<span aria-hidden="true">◌</span> Starting`;
  $("#stopBtn").disabled = false;
  $("#batchProgressCard").hidden = false;
  $("#batchProgressFill").style.width = "0%";
  $("#batchCount").textContent = `0 / ${API.files.length} done`;
  $("#batchRate").textContent = "- files/s";
  $("#batchETA").textContent = "ETA -";
  $("#progressCaption").textContent = "Preparing the queue.";
  $("#batchSavings").hidden = true;
  appendLog("Starting premium batch compression...");

  saveSettings();
  const res = await fetch(`/api/session/${API.session}/compress`, { method: "POST" });
  const data = await res.json();
  if (data.error) {
    API.compressing = false;
    $("#compressBtn").innerHTML = `<span aria-hidden="true">▶</span> Compress Queue`;
    $("#stopBtn").disabled = true;
    updateCompressBtn();
    toast(data.error, "error");
  }
}

async function stopCompression() {
  await fetch(`/api/session/${API.session}/stop`, { method: "POST" });
  $("#progressCaption").textContent = "Stopping after active work exits.";
}

function clearFiles() {
  if (API.compressing) return;
  API.objectUrls.forEach((url) => URL.revokeObjectURL(url));
  API.objectUrls.clear();
  API.files = [];
  API.previewFileId = null;
  renderQueue();
  updateAllMetrics();
  $("#batchProgressCard").hidden = true;
  $("#downloadAllBtn").disabled = true;
  $("#compressBtn").disabled = true;
  $("#clearFilesBtn").disabled = true;
  $("#previewArea").innerHTML = `<p class="preview-placeholder">Preview will appear here</p>`;
  $("#previewHint").textContent = "Select a queued image to inspect compression detail.";
  $("#previewSliderRow").hidden = true;
  $("#previewQualityRow").hidden = true;
  $("#zoomPreviewBtn").disabled = true;
}

function clearSession() {
  if (API.compressing) return;
  fetch(`/api/session/${API.session}`, { method: "DELETE" }).catch(() => {});
  if (API.ws) API.ws.close();
  clearFiles();
  API.session = null;
  init();
}

function bindEvents() {
  $("#fileInput").addEventListener("change", (e) => {
    if (e.target.files.length) addFilesToQueue(e.target.files);
    e.target.value = "";
  });
  $("#dropZone").addEventListener("click", () => $("#fileInput").click());

  let dragCounter = 0;
  const dz = $("#dropZone");
  dz.addEventListener("dragenter", (e) => {
    e.preventDefault();
    dragCounter++;
    dz.classList.add("dragover");
    $("#dropActive").hidden = false;
  });
  dz.addEventListener("dragover", (e) => e.preventDefault());
  dz.addEventListener("dragleave", (e) => {
    e.preventDefault();
    dragCounter--;
    if (dragCounter <= 0) {
      dragCounter = 0;
      dz.classList.remove("dragover");
      $("#dropActive").hidden = true;
    }
  });
  dz.addEventListener("drop", (e) => {
    e.preventDefault();
    dragCounter = 0;
    dz.classList.remove("dragover");
    $("#dropActive").hidden = true;
    if (e.dataTransfer.files.length) addFilesToQueue(e.dataTransfer.files);
  });

  $$(".preset").forEach((btn) => {
    btn.addEventListener("click", () => {
      $$(".preset").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      $("#customSizeRow").hidden = btn.dataset.value !== "";
      saveSettings();
    });
  });

  ["customSizeInput", "customSizeUnit", "outputFormat", "nameMode", "minSide", "keepMetadata"].forEach((id) => {
    const event = id === "customSizeInput" ? "input" : "change";
    $(`#${id}`).addEventListener(event, saveSettings);
  });

  $("#minQuality").addEventListener("input", () => {
    $("#minQualityLabel").textContent = $("#minQuality").value;
    if (parseInt($("#minQuality").value, 10) > parseInt($("#maxQuality").value, 10)) {
      $("#maxQuality").value = $("#minQuality").value;
      $("#maxQualityLabel").textContent = $("#minQuality").value;
    }
    saveSettings();
  });
  $("#maxQuality").addEventListener("input", () => {
    $("#maxQualityLabel").textContent = $("#maxQuality").value;
    if (parseInt($("#maxQuality").value, 10) < parseInt($("#minQuality").value, 10)) {
      $("#minQuality").value = $("#maxQuality").value;
      $("#minQualityLabel").textContent = $("#maxQuality").value;
    }
    saveSettings();
  });

  $("#compareSlider").addEventListener("input", updateCompareReveal);
  $("#previewQuality").addEventListener("input", () => {
    $("#previewQualityLabel").textContent = $("#previewQuality").value;
    clearTimeout(API.previewDebounce);
    API.previewDebounce = setTimeout(loadPreview, 220);
  });

  $("#compressBtn").addEventListener("click", startCompression);
  $("#stopBtn").addEventListener("click", stopCompression);
  $("#clearFilesBtn").addEventListener("click", clearFiles);
  $("#downloadAllBtn").addEventListener("click", downloadAll);
  $("#clearLogBtn").addEventListener("click", () => {
    $("#logArea").innerHTML = '<div class="log-empty">Ready to compress</div>';
  });
  $("#clearSessionBtn").addEventListener("click", clearSession);
  $("#zoomPreviewBtn").addEventListener("click", openPreviewDialog);
  $("#closePreviewDialog").addEventListener("click", () => $("#previewDialog").close());
}

function openPreviewDialog() {
  const img = $("#compareAfterImage") || $(".compare-before");
  if (!img?.src) return;
  $("#zoomPreviewImage").src = img.src;
  $("#previewDialog").showModal();
}

function updateAllMetrics() {
  const totalSource = API.files.reduce((sum, f) => sum + (f.source_size || 0), 0);
  const totalOutput = API.files.reduce((sum, f) => sum + (f.output_size || estimatedOutputSize(f.source_size || 0)), 0);
  const saved = Math.max(totalSource - totalOutput, 0);
  const done = API.files.filter((f) => terminalStatus(normalizeStatus(f.status))).length;
  const ratio = totalSource ? Math.round((saved / totalSource) * 100) : 0;

  $("#queueOriginalMetric").textContent = `${humanSize(totalSource) || "0 B"} queued`;
  $("#queueCompressedMetric").textContent = `${humanSize(totalOutput) || "0 B"} estimated`;
  $("#queueSavedMetric").textContent = `${humanSize(saved) || "0 B"} saved`;
  $("#totalSavedMetric").textContent = humanSize(saved) || "0 B";
  $("#compressionRatioMetric").textContent = `${ratio}%`;
  $("#filesProcessedMetric").textContent = `${done} / ${API.files.length}`;
  if (!API.compressing) $("#etaMetric").textContent = API.files.length ? "Ready" : "Ready";
}

function updateSmartHint() {
  const active = document.querySelector(".preset.active");
  const mode = active?.dataset.mode || "Website Ready";
  const quality = active?.dataset.quality || "High";
  const savings = active?.dataset.savings || "75-92%";
  const exts = API.files.map((f) => extensionOf(f.filename));
  let context = `${mode}: ${quality} quality, ${savings} expected savings.`;
  if (exts.includes("png")) context = `Optimized for AI artwork and PNG detail. ${context}`;
  else if (API.files.length >= 8) context = `Batch export detected. ${context}`;
  $("#smartHint").textContent = context;
}

function estimatedOutputSize(sourceSize) {
  const target = parseSize(getTargetSize());
  if (!sourceSize) return 0;
  return Math.min(sourceSize, target || sourceSize);
}

function parseSize(text) {
  const match = String(text || "").trim().toLowerCase().match(/^([0-9.]+)\s*(b|kb|mb)?$/);
  if (!match) return 500 * 1024;
  const value = parseFloat(match[1]);
  const unit = match[2] || "b";
  if (unit === "mb") return value * 1024 * 1024;
  if (unit === "kb") return value * 1024;
  return value;
}

function savingPercent(source, output) {
  if (!source) return 0;
  return Math.max(0, Math.min(99, Math.round((1 - output / source) * 100)));
}

function terminalStatus(status) {
  return ["done", "best_effort", "skipped", "failed"].includes(status);
}

function normalizeStatus(status) {
  return String(status || "queued").replace("-", "_");
}

function labelForStatus(status) {
  return status.replace("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function extensionOf(filename) {
  return (filename.split(".").pop() || "").toLowerCase();
}

function humanSize(bytes) {
  if (!bytes) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  let i = 0;
  let size = Number(bytes);
  while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
  return `${size.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function escapeHtml(s) {
  const d = document.createElement("div");
  d.textContent = s ?? "";
  return d.innerHTML;
}

document.addEventListener("DOMContentLoaded", init);
