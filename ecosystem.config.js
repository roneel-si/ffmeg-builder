module.exports = {
	apps: [
		{
			name: "ffmeg-builder",
			script: "server.js",
			instances: 1,
			exec_mode: "cluster",
			env: {
				NODE_ENV: "development",
				PORT: 3333,
				OUTPUT_PATH: "./output",
				LOG_FILE_PATH: "./logs",
			},
			env_production: {
				NODE_ENV: "production",
				PORT: 3333,
				OUTPUT_PATH: "./output",
				LOG_FILE_PATH: "./logs",
			},
			error_file: "./logs/error.log",
			out_file: "./logs/out.log",
			log_file: "./logs/combined.log",
			time: true,
			max_restarts: 10,
			min_uptime: "10s",
			max_memory_restart: "500M",
			watch: false,
			ignore_watch: ["node_modules", "logs", "output"],
			restart_delay: 4000,
		},
	],
};
