const express = require("express");
const cors = require("cors");
const bodyParser = require("body-parser");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
const { v4: uuidv4 } = require("uuid");
const winston = require("winston");
const Joi = require("joi");
const WebSocket = require("ws");
const http = require("http");

// Initialize Express app
const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Configuration
const PORT = process.env.PORT || 3000;
const OUTPUT_BASE_PATH = process.env.OUTPUT_PATH || "./output";

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_BASE_PATH)) {
	fs.mkdirSync(OUTPUT_BASE_PATH, { recursive: true });
}

// Logger configuration
const logger = winston.createLogger({
	level: "info",
	format: winston.format.combine(
		winston.format.timestamp(),
		winston.format.errors({ stack: true }),
		winston.format.json(),
	),
	defaultMeta: { service: "ffmpeg-builder" },
	transports: [
		new winston.transports.File({ filename: "error.log", level: "error" }),
		new winston.transports.File({ filename: "combined.log" }),
		new winston.transports.Console({
			format: winston.format.simple(),
		}),
	],
});

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static("public"));

// Store active processes
const activeProcesses = new Map();

// WebSocket connection handling
wss.on("connection", (ws) => {
	logger.info("WebSocket client connected");

	ws.on("close", () => {
		logger.info("WebSocket client disconnected");
	});
});

// Broadcast to all connected WebSocket clients
function broadcast(message) {
	wss.clients.forEach((client) => {
		if (client.readyState === WebSocket.OPEN) {
			client.send(JSON.stringify(message));
		}
	});
}

// Validation schemas
const srtToHlsSchema = Joi.object({
	srtAddress: Joi.string().ip().required(),
	srtPort: Joi.number().integer().min(1).max(65535).required(),
	streamId: Joi.string().optional().allow(""),
	passphrase: Joi.string().optional().allow(""),
	outputPath: Joi.string().required(),
	hlsName: Joi.string().required(),
});

const hlsToMp4Schema = Joi.object({
	hlsInputUrl: Joi.string().uri().required(),
	outputPath: Joi.string().required(),
	mp4Name: Joi.string().required(),
});

// Utility function to sanitize file paths
function sanitizePath(inputPath) {
	return path.normalize(inputPath).replace(/^(\.\.[\/\\])+/, "");
}

// Build SRT to HLS FFmpeg command
function buildSrtToHlsCommand(params) {
	const { srtAddress, srtPort, streamId, passphrase, outputPath, hlsName } =
		params;

	// Build SRT URL with conditional parameters
	let srtUrl = `srt://${srtAddress}:${srtPort}?mode=caller`;

	if (passphrase && passphrase.trim()) {
		srtUrl += `&passphrase=${encodeURIComponent(passphrase)}&pbkeylen=16`;
	}

	if (streamId && streamId.trim()) {
		srtUrl += `&streamid=${encodeURIComponent(streamId)}`;
	}

	// Add remaining SRT parameters
	srtUrl += `&recvbuf=100000000&latency=4000&maxbw=8000000&reconnect=1&reconnect_delay=500&reconnect_max_delay=10000`;

	const sanitizedOutputPath = sanitizePath(outputPath);
	const fullOutputPath = path.join(OUTPUT_BASE_PATH, sanitizedOutputPath);
	const segmentPrefix = path.join(fullOutputPath, `${hlsName}_segment`);
	const playlistPath = path.join(fullOutputPath, `${hlsName}.m3u8`);

	// Ensure output directory exists
	if (!fs.existsSync(fullOutputPath)) {
		fs.mkdirSync(fullOutputPath, { recursive: true });
	}

	return [
		"ffmpeg",
		[
			"-nostdin",
			"-fflags",
			"+genpts+discardcorrupt+igndts+flush_packets",
			"-err_detect",
			"ignore_err",
			"-rw_timeout",
			"15000000",
			"-analyzeduration",
			"10M",
			"-probesize",
			"50M",
			"-i",
			srtUrl,
			"-map",
			"0:v:0",
			"-map",
			"0:a",
			"-c:v",
			"libx264",
			"-preset",
			"medium",
			"-crf",
			"20",
			"-r",
			"50",
			"-g",
			"300",
			"-keyint_min",
			"300",
			"-sc_threshold",
			"0",
			"-pix_fmt",
			"yuv420p",
			"-c:a",
			"aac",
			"-ac",
			"2",
			"-b:a",
			"128k",
			"-dn",
			"-f",
			"hls",
			"-hls_time",
			"6",
			"-hls_list_size",
			"0",
			"-hls_flags",
			"independent_segments+append_list",
			"-hls_segment_filename",
			`${segmentPrefix}_%03d.ts`,
			"-movflags",
			"+faststart",
			"-y",
			playlistPath,
		],
	];
}

// Build HLS to MP4 FFmpeg command
function buildHlsToMp4Command(params) {
	const { hlsInputUrl, outputPath, mp4Name } = params;

	const sanitizedOutputPath = sanitizePath(outputPath);
	const fullOutputPath = path.join(OUTPUT_BASE_PATH, sanitizedOutputPath);
	const mp4Path = path.join(fullOutputPath, `${mp4Name}.mp4`);

	// Ensure output directory exists
	if (!fs.existsSync(fullOutputPath)) {
		fs.mkdirSync(fullOutputPath, { recursive: true });
	}

	return [
		"ffmpeg",
		[
			"-fflags",
			"+genpts+discardcorrupt",
			"-reconnect",
			"1",
			"-reconnect_streamed",
			"1",
			"-reconnect_delay_max",
			"2",
			"-i",
			hlsInputUrl,
			"-map",
			"0:v:0",
			"-map",
			"0:a:0",
			"-c:v",
			"copy",
			"-c:a",
			"aac",
			"-b:a",
			"128k",
			"-profile:a",
			"aac_low",
			"-bsf:a",
			"aac_adtstoasc",
			"-movflags",
			"+faststart+frag_keyframe+empty_moov",
			"-y",
			mp4Path,
		],
	];
}

// Execute FFmpeg command
function executeFFmpeg(command, args, processId, conversionType) {
	return new Promise((resolve, reject) => {
		logger.info(`Starting ${conversionType} conversion`, {
			processId,
			command: `${command} ${args.join(" ")}`,
		});

		const ffmpegProcess = spawn(command, args);
		activeProcesses.set(processId, ffmpegProcess);

		let stderr = "";
		let stdout = "";

		ffmpegProcess.stdout.on("data", (data) => {
			stdout += data.toString();
			broadcast({
				type: "progress",
				processId,
				data: data.toString(),
				timestamp: new Date().toISOString(),
			});
		});

		ffmpegProcess.stderr.on("data", (data) => {
			stderr += data.toString();
			broadcast({
				type: "progress",
				processId,
				data: data.toString(),
				timestamp: new Date().toISOString(),
			});
		});

		ffmpegProcess.on("close", (code) => {
			activeProcesses.delete(processId);

			if (code === 0) {
				logger.info(
					`${conversionType} conversion completed successfully`,
					{ processId },
				);
				broadcast({
					type: "completed",
					processId,
					message: `${conversionType} conversion completed successfully`,
					timestamp: new Date().toISOString(),
				});
				resolve({ success: true, output: stdout, processId });
			} else {
				logger.error(`${conversionType} conversion failed`, {
					processId,
					code,
					stderr,
				});
				broadcast({
					type: "error",
					processId,
					message: `${conversionType} conversion failed with code ${code}`,
					error: stderr,
					timestamp: new Date().toISOString(),
				});
				reject(
					new Error(
						`FFmpeg process exited with code ${code}: ${stderr}`,
					),
				);
			}
		});

		ffmpegProcess.on("error", (error) => {
			activeProcesses.delete(processId);
			logger.error(`${conversionType} conversion error`, {
				processId,
				error: error.message,
			});
			broadcast({
				type: "error",
				processId,
				message: `${conversionType} conversion error: ${error.message}`,
				timestamp: new Date().toISOString(),
			});
			reject(error);
		});
	});
}

// API Routes

// Health check
app.get("/api/health", (req, res) => {
	res.json({ status: "healthy", timestamp: new Date().toISOString() });
});

// Get active processes
app.get("/api/processes", (req, res) => {
	const processes = Array.from(activeProcesses.keys());
	res.json({ activeProcesses: processes });
});

// SRT to HLS conversion
app.post("/api/convert/srt-to-hls", async (req, res) => {
	try {
		const { error, value } = srtToHlsSchema.validate(req.body);
		if (error) {
			return res.status(400).json({
				error: "Validation failed",
				details: error.details.map((d) => d.message),
			});
		}

		const processId = uuidv4();
		const [command, args] = buildSrtToHlsCommand(value);

		// Send immediate response with process ID
		res.json({
			message: "SRT to HLS conversion started",
			processId,
			timestamp: new Date().toISOString(),
		});

		// Start conversion asynchronously
		executeFFmpeg(command, args, processId, "SRT to HLS").catch((error) => {
			logger.error("SRT to HLS conversion failed", {
				processId,
				error: error.message,
			});
		});
	} catch (error) {
		logger.error("SRT to HLS API error", { error: error.message });
		res.status(500).json({
			error: "Internal server error",
			message: error.message,
		});
	}
});

// HLS to MP4 conversion
app.post("/api/convert/hls-to-mp4", async (req, res) => {
	try {
		const { error, value } = hlsToMp4Schema.validate(req.body);
		if (error) {
			return res.status(400).json({
				error: "Validation failed",
				details: error.details.map((d) => d.message),
			});
		}

		const processId = uuidv4();
		const [command, args] = buildHlsToMp4Command(value);

		// Send immediate response with process ID
		res.json({
			message: "HLS to MP4 conversion started",
			processId,
			timestamp: new Date().toISOString(),
		});

		// Start conversion asynchronously
		executeFFmpeg(command, args, processId, "HLS to MP4").catch((error) => {
			logger.error("HLS to MP4 conversion failed", {
				processId,
				error: error.message,
			});
		});
	} catch (error) {
		logger.error("HLS to MP4 API error", { error: error.message });
		res.status(500).json({
			error: "Internal server error",
			message: error.message,
		});
	}
});

// Stop conversion
app.post("/api/stop/:processId", (req, res) => {
	const { processId } = req.params;
	const process = activeProcesses.get(processId);

	if (process) {
		process.kill("SIGTERM");
		activeProcesses.delete(processId);
		logger.info("Process stopped", { processId });
		res.json({ message: "Process stopped", processId });
	} else {
		res.status(404).json({ error: "Process not found", processId });
	}
});

// Error handling middleware
app.use((error, req, res, next) => {
	logger.error("Unhandled error", {
		error: error.message,
		stack: error.stack,
	});
	res.status(500).json({ error: "Internal server error" });
});

// Start server
server.listen(PORT, () => {
	logger.info(`FFmpeg Builder server running on port ${PORT}`);
	console.log(`Server running on http://localhost:${PORT}`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
	logger.info("SIGTERM received, shutting down gracefully");
	server.close(() => {
		logger.info("HTTP server closed");
		process.exit(0);
	});
});

process.on("SIGINT", () => {
	logger.info("SIGINT received, shutting down gracefully");
	server.close(() => {
		logger.info("HTTP server closed");
		process.exit(0);
	});
});
