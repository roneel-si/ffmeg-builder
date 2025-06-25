// FFmpeg Builder Frontend Application
class FFmpegBuilder {
	constructor() {
		this.ws = null;
		this.activeProcesses = new Map();
		this.logContainer = document.getElementById("log-output");
		this.processesContainer = document.getElementById(
			"processes-container",
		);

		this.init();
	}

	init() {
		this.setupEventListeners();
		this.connectWebSocket();
		this.loadActiveProcesses();
	}

	setupEventListeners() {
		// Form submissions
		document
			.getElementById("srt-form")
			.addEventListener("submit", this.handleSrtForm.bind(this));
		document
			.getElementById("hls-form")
			.addEventListener("submit", this.handleHlsForm.bind(this));

		// Preview buttons
		document
			.getElementById("preview-srt")
			.addEventListener("click", this.previewSrtCommand.bind(this));
		document
			.getElementById("preview-hls")
			.addEventListener("click", this.previewHlsCommand.bind(this));

		// Modal controls
		document
			.getElementById("close-modal")
			.addEventListener("click", this.closeModal.bind(this));
		document
			.getElementById("copy-command")
			.addEventListener("click", this.copyCommand.bind(this));
		document
			.getElementById("command-modal")
			.addEventListener("click", (e) => {
				if (e.target.id === "command-modal") {
					this.closeModal();
				}
			});

		// Log controls
		document
			.getElementById("clear-log")
			.addEventListener("click", this.clearLog.bind(this));
		document
			.getElementById("toggle-log")
			.addEventListener("click", this.toggleLog.bind(this));

		// Keyboard shortcuts
		document.addEventListener("keydown", (e) => {
			if (e.key === "Escape") {
				this.closeModal();
			}
		});
	}

	connectWebSocket() {
		const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
		const wsUrl = `${protocol}//${window.location.host}`;

		this.ws = new WebSocket(wsUrl);

		this.ws.onopen = () => {
			console.log("WebSocket connected");
			this.showNotification("Connected to server", "success");
		};

		this.ws.onmessage = (event) => {
			try {
				const message = JSON.parse(event.data);
				this.handleWebSocketMessage(message);
			} catch (error) {
				console.error("Failed to parse WebSocket message:", error);
			}
		};

		this.ws.onclose = () => {
			console.log("WebSocket disconnected");
			this.showNotification("Disconnected from server", "warning");

			// Attempt to reconnect after 3 seconds
			setTimeout(() => {
				this.connectWebSocket();
			}, 3000);
		};

		this.ws.onerror = (error) => {
			console.error("WebSocket error:", error);
			this.showNotification("Connection error", "error");
		};
	}

	handleWebSocketMessage(message) {
		const { type, processId, data, timestamp } = message;

		switch (type) {
			case "progress":
				this.updateProcessStatus(processId, "running");
				this.addLogEntry(
					`[${processId}] ${data}`,
					"progress",
					timestamp,
				);
				break;
			case "completed":
				this.updateProcessStatus(processId, "completed");
				this.addLogEntry(
					`[${processId}] ${message.message}`,
					"success",
					timestamp,
				);
				this.showNotification(
					"Conversion completed successfully",
					"success",
				);
				break;
			case "error":
				this.updateProcessStatus(processId, "error");
				this.addLogEntry(
					`[${processId}] ${message.message}`,
					"error",
					timestamp,
				);
				if (message.error) {
					this.addLogEntry(
						`[${processId}] ${message.error}`,
						"error",
						timestamp,
					);
				}
				this.showNotification("Conversion failed", "error");
				break;
		}
	}

	async handleSrtForm(e) {
		e.preventDefault();

		const form = e.target;
		const formData = new FormData(form);
		const data = Object.fromEntries(formData.entries());

		// Convert port to number
		data.srtPort = parseInt(data.srtPort, 10);

		try {
			this.setFormLoading(form, true);

			const response = await fetch("/api/convert/srt-to-hls", {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
				},
				body: JSON.stringify(data),
			});

			const result = await response.json();

			if (response.ok) {
				this.showNotification(result.message, "success");
				this.addLogEntry(
					`Started SRT to HLS conversion: ${result.processId}`,
					"progress",
				);
				this.addProcess(result.processId, "SRT to HLS", "running");
				form.reset();
			} else {
				throw new Error(result.error || "Unknown error");
			}
		} catch (error) {
			console.error("SRT to HLS conversion error:", error);
			this.showNotification(`Error: ${error.message}`, "error");
			this.addLogEntry(
				`SRT to HLS conversion error: ${error.message}`,
				"error",
			);
		} finally {
			this.setFormLoading(form, false);
		}
	}

	async handleHlsForm(e) {
		e.preventDefault();

		const form = e.target;
		const formData = new FormData(form);
		const data = Object.fromEntries(formData.entries());

		try {
			this.setFormLoading(form, true);

			const response = await fetch("/api/convert/hls-to-mp4", {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
				},
				body: JSON.stringify(data),
			});

			const result = await response.json();

			if (response.ok) {
				this.showNotification(result.message, "success");
				this.addLogEntry(
					`Started HLS to MP4 conversion: ${result.processId}`,
					"progress",
				);
				this.addProcess(result.processId, "HLS to MP4", "running");
				form.reset();
			} else {
				throw new Error(result.error || "Unknown error");
			}
		} catch (error) {
			console.error("HLS to MP4 conversion error:", error);
			this.showNotification(`Error: ${error.message}`, "error");
			this.addLogEntry(
				`HLS to MP4 conversion error: ${error.message}`,
				"error",
			);
		} finally {
			this.setFormLoading(form, false);
		}
	}

	previewSrtCommand() {
		const form = document.getElementById("srt-form");
		const formData = new FormData(form);
		const data = Object.fromEntries(formData.entries());

		if (
			!data.srtAddress ||
			!data.srtPort ||
			!data.outputPath ||
			!data.hlsName
		) {
			this.showNotification("Please fill in required fields", "warning");
			return;
		}

		// Build SRT URL with conditional parameters
		let srtUrl = `srt://${data.srtAddress}:${data.srtPort}?mode=caller`;

		if (data.passphrase && data.passphrase.trim()) {
			srtUrl += `&passphrase=${encodeURIComponent(
				data.passphrase,
			)}&pbkeylen=16`;
		}

		if (data.streamId && data.streamId.trim()) {
			srtUrl += `&streamid=${encodeURIComponent(data.streamId)}`;
		}

		// Add remaining SRT parameters
		srtUrl += `&recvbuf=100000000&latency=4000&maxbw=8000000&reconnect=1&reconnect_delay=500&reconnect_max_delay=10000`;

		const command = `ffmpeg -nostdin \\
-fflags +genpts+discardcorrupt+igndts+flush_packets \\
-err_detect ignore_err \\
-rw_timeout 15000000 \\
-analyzeduration 10M \\
-probesize 50M \\
-i "${srtUrl}" \\
-map 0:v:0 -map 0:a \\
-c:v libx264 -preset medium -crf 20 -r 50 -g 300 -keyint_min 300 -sc_threshold 0 -pix_fmt yuv420p \\
-c:a aac -ac 2 -b:a 128k \\
-dn \\
-f hls -hls_time 6 \\
-hls_list_size 0 \\
-hls_flags independent_segments+append_list \\
-hls_segment_filename "${data.outputPath}/${data.hlsName}_segment_%03d.ts" \\
-movflags +faststart \\
-y "${data.outputPath}/${data.hlsName}.m3u8"`;

		this.showCommandPreview(command);
	}

	previewHlsCommand() {
		const form = document.getElementById("hls-form");
		const formData = new FormData(form);
		const data = Object.fromEntries(formData.entries());

		if (!data.hlsInputUrl || !data.outputPath || !data.mp4Name) {
			this.showNotification("Please fill in required fields", "warning");
			return;
		}

		const command = `ffmpeg \\
-fflags +genpts+discardcorrupt \\
-reconnect 1 \\
-reconnect_streamed 1 \\
-reconnect_delay_max 2 \\
-i "${data.hlsInputUrl}" \\
-map 0:v:0 -map 0:a:0 \\
-c:v copy \\
-c:a aac -b:a 128k -profile:a aac_low \\
-bsf:a aac_adtstoasc \\
-movflags +faststart+frag_keyframe+empty_moov \\
-y "${data.outputPath}/${data.mp4Name}.mp4"`;

		this.showCommandPreview(command);
	}

	showCommandPreview(command) {
		document.getElementById("command-preview").textContent = command;
		document.getElementById("command-modal").style.display = "block";
	}

	closeModal() {
		document.getElementById("command-modal").style.display = "none";
	}

	async copyCommand() {
		const command = document.getElementById("command-preview").textContent;

		try {
			await navigator.clipboard.writeText(command);
			this.showNotification("Command copied to clipboard", "success");
		} catch (error) {
			console.error("Failed to copy command:", error);
			this.showNotification("Failed to copy command", "error");
		}
	}

	setFormLoading(form, loading) {
		const submitButton = form.querySelector('button[type="submit"]');
		const previewButton = form.querySelector('button[type="button"]');

		if (loading) {
			submitButton.disabled = true;
			submitButton.classList.add("loading");
			previewButton.disabled = true;
		} else {
			submitButton.disabled = false;
			submitButton.classList.remove("loading");
			previewButton.disabled = false;
		}
	}

	addProcess(processId, type, status) {
		const processItem = document.createElement("div");
		processItem.className = "process-item";
		processItem.id = `process-${processId}`;

		processItem.innerHTML = `
            <div class="process-info">
                <span class="process-type">${type}</span>
                <span class="process-id">${processId.substring(0, 8)}</span>
                <span class="process-status status-${status}">${status.toUpperCase()}</span>
            </div>
            <button class="btn btn-secondary" onclick="app.stopProcess('${processId}')">Stop</button>
        `;

		// Remove "no processes" message if it exists
		const noProcesses =
			this.processesContainer.querySelector(".no-processes");
		if (noProcesses) {
			noProcesses.remove();
		}

		this.processesContainer.appendChild(processItem);
		this.activeProcesses.set(processId, { type, status });
	}

	updateProcessStatus(processId, status) {
		const processItem = document.getElementById(`process-${processId}`);
		if (processItem) {
			const statusSpan = processItem.querySelector(".process-status");
			if (statusSpan) {
				statusSpan.className = `process-status status-${status}`;
				statusSpan.textContent = status.toUpperCase();
			}

			// Remove stop button for completed/error processes
			if (status === "completed" || status === "error") {
				const stopButton = processItem.querySelector("button");
				if (stopButton) {
					stopButton.remove();
				}

				// Auto-remove after 10 seconds
				setTimeout(() => {
					this.removeProcess(processId);
				}, 10000);
			}
		}

		// Update local state
		const process = this.activeProcesses.get(processId);
		if (process) {
			process.status = status;
		}
	}

	removeProcess(processId) {
		const processItem = document.getElementById(`process-${processId}`);
		if (processItem) {
			processItem.remove();
		}

		this.activeProcesses.delete(processId);

		// Show "no processes" message if no active processes
		if (this.activeProcesses.size === 0) {
			this.processesContainer.innerHTML =
				'<p class="no-processes">No active processes</p>';
		}
	}

	async stopProcess(processId) {
		try {
			const response = await fetch(`/api/stop/${processId}`, {
				method: "POST",
			});

			const result = await response.json();

			if (response.ok) {
				this.showNotification("Process stopped", "success");
				this.removeProcess(processId);
			} else {
				throw new Error(result.error || "Unknown error");
			}
		} catch (error) {
			console.error("Stop process error:", error);
			this.showNotification(
				`Error stopping process: ${error.message}`,
				"error",
			);
		}
	}

	async loadActiveProcesses() {
		try {
			const response = await fetch("/api/processes");
			const result = await response.json();

			result.activeProcesses.forEach((processId) => {
				this.addProcess(processId, "Unknown", "running");
			});
		} catch (error) {
			console.error("Failed to load active processes:", error);
		}
	}

	addLogEntry(message, type = "info", timestamp = null) {
		const logEntry = document.createElement("div");
		logEntry.className = `log-entry log-${type}`;

		const time = timestamp
			? new Date(timestamp).toLocaleTimeString()
			: new Date().toLocaleTimeString();
		logEntry.innerHTML = `<span class="log-timestamp">[${time}]</span> ${message}`;

		this.logContainer.appendChild(logEntry);
		this.logContainer.scrollTop = this.logContainer.scrollHeight;
	}

	clearLog() {
		this.logContainer.innerHTML = "";
		this.showNotification("Log cleared", "success");
	}

	toggleLog() {
		const logContainer = document.getElementById("log-container");
		logContainer.classList.toggle("hidden");
	}

	showNotification(message, type = "info") {
		const notification = document.createElement("div");
		notification.className = `notification ${type}`;

		notification.innerHTML = `
            <div class="notification-content">
                <div class="notification-message">${message}</div>
                <button class="notification-close">&times;</button>
            </div>
        `;

		const container = document.getElementById("notification-container");
		container.appendChild(notification);

		// Auto-remove after 5 seconds
		setTimeout(() => {
			if (notification.parentNode) {
				notification.remove();
			}
		}, 5000);

		// Manual close
		notification
			.querySelector(".notification-close")
			.addEventListener("click", () => {
				notification.remove();
			});
	}
}

// Initialize the application when DOM is loaded
document.addEventListener("DOMContentLoaded", () => {
	window.app = new FFmpegBuilder();
});

// Global function for process stopping (called from HTML)
window.stopProcess = function (processId) {
	if (window.app) {
		window.app.stopProcess(processId);
	}
};
