import { sveltekit } from "@sveltejs/kit/vite";
import Icons from "unplugin-icons/vite";
import { defineConfig, loadEnv, type Plugin } from "vite";

import { checkEnvIsolation, formatGuardError } from "./scripts/env_isolation.mjs";

function envIsolationGuard(): Plugin {
	return {
		name: "env-isolation-guard",
		config(_config, { command, mode }) {
			if (command !== "serve") return;
			const env = loadEnv(mode, process.cwd(), "");
			const merged = { ...process.env, ...env };
			const result = checkEnvIsolation(merged);
			if (result.override) {
				console.warn(
					"\n[env-isolation] ALLOW_PROD_URL_IN_DEV=true — guard bypassed. " +
						"This is a power-user override; do not commit a setup that depends on it.\n",
				);
				return;
			}
			if (!result.ok) {
				throw new Error(formatGuardError(result, { scope: "vite" }));
			}
		},
	};
}

export default defineConfig({
	plugins: [
		envIsolationGuard(),
		sveltekit(),
		Icons({
			autoInstall: true,
			compiler: "svelte",
		}),
	],
});
