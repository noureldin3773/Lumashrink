const API = {
  session: null,
  ws: null,
  compressing: false,
  files: [],
  previewFileId: null,
  previewDebounce: null,
};

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

async function init() {
  const res = await fetch("/api/session", { method: "POST" });
  const data = await res.json();
  API.session = data.session_id;
  $("#sessionBadge").textContent = `Session: ${API.session}`;
  connectWS();
  bindEvents();
}

function toast(msg, type = "info") {
  const el = document.createElement("div");
  el.className = `toast ${type}`;
  el.textContent = msg;
  $("#toastContainer").appendChild(el);
  setTimeout(() => el.remove(), 3000);
}

// --- WebSocket ---
function connectWS() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const url = `${proto}//${location.host}/api/session/${API.session}/ws`;
  API.ws = new WebSocket(url);
  API.ws.onmessage = (e) => {
    try {
      const msg = JSON.parse(e.data);
      handleWSMessage(msg);
    } catch {}
  };
  API.ws.onclose = () => {
    if (!API.compressing) setTimeout(connectWS, 2000);
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

// --- File Queue ---
function addFilesToQueue(fileList) {
  const formData = new FormData();
  for (const f of fileList) formData.append("files", f);

  fetch(`/api/session/${API.session}/upload`, { method: "POST", body: formData })
    .then((r) => r.json())
    .then((data) => {
      if (data.error) return toast(data.error, "error");
      for (const f of data.files) {
        API.files.push(f);
      }
      renderQueue();
      updateCompressBtn();
    })
    .catch(() => toast("Upload failed", "error"));
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
    return;
  }

  empty.hidden = true;
  table.hidden = false;
  $("#fileCount").textContent = `${API.files.length} file${API.files.length !== 1 ? "s" : ""}`;
  $("#clearFilesBtn").disabled = false;

  list.innerHTML = API.files.map((f) => {
    const sizeStr = humanSize(f.source_size);
    const statusClass = f.status || "queued";
    const progressPct = statusClass === "processing" ? "62" : ["done", "best_effort", "skipped", "failed"].includes(statusClass) ? "100" : "0";
    const statusLabel = statusClass.charAt(0).toUpperCase() + statusClass.slice(1).replace("_", " ");

    let statusHtml = `<span class="queue-status ${statusClass}">${statusLabel}</span>`;
    if (f.status === "done" && f.file_id) {
      statusHtml = `<span class="queue-status ${statusClass}">${statusLabel} <a class="download-link" data-file-id="${f.file_id}" onclick="downloadFile('${f.file_id}')">download</a></span>`;
    }

    const ext = f.filename.split(".").pop().toLowerCase();
    const isVideo = ["mp4","mov","avi","mkv","webm","m4v","wmv","flv"].includes(ext);
    const isImage = ["jpg","jpeg","png","gif","webp","bmp","tiff","tif","heic","heif"].includes(ext);

    let iconSvg;
    if (isVideo) {
      iconSvg = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>`;
    } else {
      iconSvg = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8" cy="8.5" r="1.5"/><path d="M21 15l-5-5L6 21"/></svg>`;
    }

    return `<div class="queue-item" data-file-id="${f.file_id}" data-file-ext="${ext}" onclick="selectPreview('${f.file_id}')">
      <div class="queue-icon" data-file-id="${f.file_id}">${iconSvg}</div>
      <div class="queue-info">
        <div class="queue-name">${escapeHtml(f.filename)}</div>
        <div class="queue-meta">${ext.toUpperCase()} | ${sizeStr}</div>
      </div>
      ${statusHtml}
      <div class="queue-progress"><div class="queue-progress-bar ${statusClass}" style="width:${progressPct}%"></div></div>
    </div>`;
  }).join("");

  loadThumbnails();
}

function loadThumbnails() {
  const icons = document.querySelectorAll(".queue-icon[data-file-id]");
  icons.forEach((el) => {
    // Skip if thumbnail already loaded
    if (el.querySelector("img")) return;
    const fileId = el.dataset.fileId;
    const item = el.closest(".queue-item");
    if (!item) return;
    const ext = item.dataset.fileExt || "";
    const isImage = ["jpg","jpeg","png","gif","webp","bmp","tiff","tif","heic","heif"].includes(ext.toLowerCase());
    if (!isImage) return;

    const img = new Image();
    img.onload = () => {
      el.innerHTML = "";
      el.appendChild(img);
    };
    img.onerror = () => {};
    img.src = `/api/session/${API.session}/raw/${fileId}`;
  });
}

function updateFileStatus(fileId, status, outputSize, detail) {
  const f = API.files.find((x) => x.file_id === fileId);
  if (!f) return;
  f.status = status;
  f.output_size = outputSize;
  f.detail = detail;
  renderQueue();
}

function updateCompressBtn() {
  const btn = $("#compressBtn");
  const hasFiles = API.files.length > 0;
  btn.disabled = !hasFiles || API.compressing;
}

// --- Batch Progress ---
function updateBatchStats(completed, total, rate, eta, totalSource, totalOutput, savingsPct) {
  const card = $("#batchProgressCard");
  card.hidden = false;
  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;
  $("#batchProgressFill").style.width = `${Math.min(pct, 100)}%`;
  $("#batchCount").textContent = `${completed} / ${total} done`;
  $("#batchRate").textContent = `${rate} files/s`;
  $("#batchETA").textContent = eta > 0 ? `ETA ${Math.round(eta)}s` : "ETA —";

  // Savings display
  const savingsEl = document.getElementById("batchSavings");
  if (totalSource && totalOutput !== undefined) {
    const saved = totalSource - totalOutput;
    savingsEl.textContent = `${humanSize(totalSource)} → ${humanSize(totalOutput)} (${savingsPct}% saved)`;
    savingsEl.style.display = "";
  }
}

function onBatchStart(total) {
  // UI already set by startCompression; just sync compressing flag
  API.compressing = true;
}

function onBatchComplete(summary, totalSource, totalOutput, savingsPct) {
  API.compressing = false;
  $("#compressBtn").disabled = false;
  $("#stopBtn").disabled = true;
  $("#compressBtn").innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg> Compress`;
  updateCompressBtn();

  let finalSummary = summary;
  if (totalSource && totalOutput !== undefined) {
    const saved = totalSource - totalOutput;
    finalSummary += ` | ${humanSize(totalSource)} → ${humanSize(totalOutput)} (${savingsPct}% saved)`;
  }
  appendLog(finalSummary);
  toast(finalSummary, summary.includes("error") ? "error" : "success");

  const hasOutput = API.files.some((f) => f.status === "done" || f.status === "best_effort");
  $("#downloadAllBtn").disabled = !hasOutput;
}

// --- Log ---
function appendLog(line) {
  const area = $("#logArea");
  const empty = area.querySelector(".log-empty");
  if (empty) empty.remove();

  const el = document.createElement("div");
  el.className = "log-line info";

  const fileTagMatch = line.match(/^\[([a-z0-9_]+)\]/);
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

// --- Preview ---
function selectPreview(fileId) {
  API.previewFileId = fileId;
  const f = API.files.find((x) => x.file_id === fileId);
  if (!f) return;

  const area = $("#previewArea");
  area.innerHTML = `<img id="previewImage" src="" alt="preview"><div class="preview-stats" id="previewStats">
    <span id="previewOriginal">Original: ${humanSize(f.source_size)}</span>
    <span id="previewCompressed">${f.output_size ? "Compressed: " + humanSize(f.output_size) : ""}</span>
  </div>`;
  $("#previewSliderRow").hidden = false;
  $("#previewQuality").value = 80;
  $("#previewQualityLabel").textContent = "80";
  loadPreview();
}

function loadPreview() {
  if (!API.previewFileId) return;
  const f = API.files.find((x) => x.file_id === API.previewFileId);
  if (!f) return;

  const quality = parseInt($("#previewQuality").value);
  const formData = new FormData();

  fetch(`/api/session/${API.session}/raw/${API.previewFileId}`)
    .then((r) => r.blob())
    .then((blob) => {
      formData.append("file", blob, f.filename);
      formData.append("max_size", getTargetSize());
      formData.append("quality", quality);
      return fetch("/api/preview", { method: "POST", body: formData });
    })
    .then((r) => {
      // Read preview from the response as base64 for the img src
      return r.blob().then((blob) => {
        const url = URL.createObjectURL(blob);
        const img = document.getElementById("previewImage") || document.querySelector("#previewArea img");
        if (img) {
          img.src = url;
          img.hidden = false;
          img.onload = () => URL.revokeObjectURL(url);
        }
        const compressed = r.headers.get("X-Output-Size");
        if (compressed) {
          const el = document.getElementById("previewCompressed");
          if (el) el.textContent = "Compressed: " + humanSize(parseInt(compressed));
        }
      });
    })
    .catch(() => {});
}

// --- Downloads ---
function downloadFile(fileId) {
  window.open(`/api/session/${API.session}/download/${fileId}`, "_blank");
}

function downloadAll() {
  window.open(`/api/session/${API.session}/download-all`, "_blank");
}

// --- Settings ---
function getTargetSize() {
  const active = document.querySelector(".preset.active");
  if (active && active.dataset.value) return active.dataset.value;
  const val = $("#customSizeInput").value.trim();
  const unit = $("#customSizeUnit").value;
  if (val) return val + unit;
  return "150kb";
}

function getSettings() {
  return {
    max_size: getTargetSize(),
    output_format: $("#outputFormat").value,
    name_mode: $("#nameMode").value,
    min_quality: parseInt($("#minQuality").value),
    max_quality: parseInt($("#maxQuality").value),
    min_side: parseInt($("#minSide").value),
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
}

// --- Compression ---
async function startCompression() {
  if (API.compressing || API.files.length === 0) return;

  // Immediately enter compressing state so UI reacts
  API.compressing = true;
  $("#compressBtn").disabled = true;
  $("#compressBtn").innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg> Starting...`;
  $("#stopBtn").disabled = false;
  $("#batchProgressCard").hidden = false;
  $("#batchProgressFill").style.width = "0%";
  const total = API.files.length;
  $("#batchCount").textContent = `0 / ${total} done`;
  appendLog("Starting batch compression...");

  saveSettings();
  const res = await fetch(`/api/session/${API.session}/compress`, { method: "POST" });
  const data = await res.json();
  if (data.error) {
    API.compressing = false;
    $("#compressBtn").disabled = false;
    $("#compressBtn").innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg> Compress`;
    $("#stopBtn").disabled = true;
    return toast(data.error, "error");
  }
}

async function stopCompression() {
  await fetch(`/api/session/${API.session}/stop`, { method: "POST" });
}

function clearFiles() {
  if (API.compressing) return;
  API.files = [];
  renderQueue();
  $("#batchProgressCard").hidden = true;
  $("#downloadAllBtn").disabled = true;
  $("#compressBtn").disabled = true;
  $("#clearFilesBtn").disabled = true;
  const area = $("#previewArea");
  area.innerHTML = `<p class="preview-placeholder">Select a queued file to preview</p>`;
  $("#previewSliderRow").hidden = true;
}

function clearSession() {
  if (API.compressing) return;
  fetch(`/api/session/${API.session}`, { method: "DELETE" }).catch(() => {});
  API.files = [];
  API.ws.close();
  init();
}

// --- Events ---
function bindEvents() {
  // File input
  $("#fileInput").addEventListener("change", (e) => {
    if (e.target.files.length) addFilesToQueue(e.target.files);
    e.target.value = "";
  });
  $("#fileInputLink").addEventListener("click", (e) => {
    e.preventDefault();
    $("#fileInput").click();
  });
  // Click the whole drop zone to open file picker
  $("#dropZone").addEventListener("click", () => $("#fileInput").click());

  // Drag-drop (counter to avoid child-element flicker)
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

  // Settings presets
  $$(".preset").forEach((btn) => {
    btn.addEventListener("click", () => {
      $$(".preset").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      $("#customSizeRow").hidden = btn.dataset.value !== "";
      saveSettings();
    });
  });
  $("#customSizeInput").addEventListener("input", saveSettings);
  $("#customSizeUnit").addEventListener("change", saveSettings);

  // Other settings
  $("#outputFormat").addEventListener("change", saveSettings);
  $("#nameMode").addEventListener("change", saveSettings);
  $("#minSide").addEventListener("change", saveSettings);
  $("#keepMetadata").addEventListener("change", saveSettings);

  // Quality sliders
  $("#minQuality").addEventListener("input", () => {
    $("#minQualityLabel").textContent = $("#minQuality").value;
    if (parseInt($("#minQuality").value) > parseInt($("#maxQuality").value)) {
      $("#maxQuality").value = $("#minQuality").value;
      $("#maxQualityLabel").textContent = $("#minQuality").value;
    }
    saveSettings();
  });
  $("#maxQuality").addEventListener("input", () => {
    $("#maxQualityLabel").textContent = $("#maxQuality").value;
    if (parseInt($("#maxQuality").value) < parseInt($("#minQuality").value)) {
      $("#minQuality").value = $("#maxQuality").value;
      $("#minQualityLabel").textContent = $("#maxQuality").value;
    }
    saveSettings();
  });

  // Preview slider
  $("#previewQuality").addEventListener("input", () => {
    $("#previewQualityLabel").textContent = $("#previewQuality").value;
    clearTimeout(API.previewDebounce);
    API.previewDebounce = setTimeout(loadPreview, 200);
  });

  // Buttons
  $("#compressBtn").addEventListener("click", startCompression);
  $("#stopBtn").addEventListener("click", stopCompression);
  $("#clearFilesBtn").addEventListener("click", clearFiles);
  $("#downloadAllBtn").addEventListener("click", downloadAll);
  $("#clearLogBtn").addEventListener("click", () => {
    $("#logArea").innerHTML = '<div class="log-empty">Ready to compress</div>';
  });
  $("#clearSessionBtn").addEventListener("click", clearSession);
}

// --- Utils ---
function humanSize(bytes) {
  if (!bytes) return "";
  const units = ["B", "KB", "MB", "GB"];
  let i = 0;
  let size = bytes;
  while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
  return `${size.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function escapeHtml(s) {
  const d = document.createElement("div");
  d.textContent = s;
  return d.innerHTML;
}

document.addEventListener("DOMContentLoaded", init);
