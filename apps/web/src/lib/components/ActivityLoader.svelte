<script module lang="ts">
	// Per-instance sequence so multiple fuel loaders on one page don't share
	// the same <mask> id. Client-only usage (loaders appear post-mount), so a
	// module counter is safe against hydration ordering.
	let seq = 0;
</script>

<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';

	type Kind = 'run' | 'train' | 'fuel';
	let {
		kind = 'run',
		size = 48,
		label,
		color,
	}: { kind?: Kind; size?: number; label?: string; color?: string } = $props();

	const biteId = `al-bite-${seq++}`;
</script>

<span
	class="activity-loader"
	role="status"
	aria-live="polite"
	style="--sz:{size}px;{color ? `--c:${color};` : ''}"
>
	{#if kind === 'run'}
		<svg class="fig r" viewBox="0 0 120 170" aria-hidden="true">
			<ellipse class="shadow" cx="60" cy="162" rx="30" ry="6" />
			<g class="lean"><g class="body">
				<g class="th th-b back"><rect class="skin" x="55.5" y="96" width="9" height="28" rx="4.5" />
					<g class="sh sh-b"><rect class="skin" x="56.25" y="124" width="7.5" height="28" rx="3.75" />
						<rect class="shoe" x="57" y="149" width="13" height="6" rx="3" /></g></g>
				<g class="ua ua-b back"><rect class="skin" x="56.5" y="52" width="7" height="24" rx="3.5" />
					<g class="fa fa-b"><rect class="skin" x="56.75" y="76" width="6.5" height="22" rx="3.25" />
						<circle class="skin" cx="60" cy="99" r="3.6" /></g></g>
				<g class="core">
					<rect class="skin" x="52" y="48" width="16" height="50" rx="8" />
					<rect class="skin" x="56.5" y="42" width="7" height="8" rx="3" />
					<circle class="skin" cx="60" cy="31" r="13" />
				</g>
				<g class="th th-f"><rect class="skin" x="55.5" y="96" width="9" height="28" rx="4.5" />
					<g class="sh sh-f"><rect class="skin" x="56.25" y="124" width="7.5" height="28" rx="3.75" />
						<rect class="shoe" x="57" y="149" width="13" height="6" rx="3" /></g></g>
				<g class="ua ua-f"><rect class="skin" x="56.5" y="52" width="7" height="24" rx="3.5" />
					<g class="fa fa-f"><rect class="skin" x="56.75" y="76" width="6.5" height="22" rx="3.25" />
						<circle class="skin" cx="60" cy="99" r="3.6" /></g></g>
			</g></g>
		</svg>
	{:else if kind === 'train'}
		<svg class="fig t" viewBox="0 0 120 170" aria-hidden="true">
			<ellipse class="shadow" cx="60" cy="162" rx="26" ry="6" />
			<g class="body">
				<g class="th th-b back"><rect class="skin" x="55.5" y="96" width="9" height="28" rx="4.5" />
					<g class="sh sh-b"><rect class="skin" x="56.25" y="124" width="7.5" height="28" rx="3.75" />
						<rect class="shoe" x="55" y="149" width="13" height="6" rx="3" /></g></g>
				<g class="ua ua-b back"><rect class="skin" x="56.5" y="52" width="7" height="24" rx="3.5" />
					<g class="fa fa-b"><rect class="skin" x="56.75" y="76" width="6.5" height="22" rx="3.25" />
						<g><rect class="gear" x="52" y="96.5" width="16" height="4.5" rx="2.2" />
							<circle class="gear" cx="52" cy="98.7" r="4.2" /><circle class="gear" cx="68" cy="98.7" r="4.2" /></g></g></g>
				<g class="core">
					<rect class="skin" x="52" y="48" width="16" height="50" rx="8" />
					<rect class="skin" x="56.5" y="42" width="7" height="8" rx="3" />
					<circle class="skin" cx="60" cy="31" r="13" />
				</g>
				<g class="th th-f"><rect class="skin" x="55.5" y="96" width="9" height="28" rx="4.5" />
					<g class="sh sh-f"><rect class="skin" x="56.25" y="124" width="7.5" height="28" rx="3.75" />
						<rect class="shoe" x="57" y="149" width="13" height="6" rx="3" /></g></g>
				<g class="ua ua-f"><rect class="skin" x="56.5" y="52" width="7" height="24" rx="3.5" />
					<g class="fa fa-f"><rect class="skin" x="56.75" y="76" width="6.5" height="22" rx="3.25" />
						<g><rect class="gear" x="52" y="96.5" width="16" height="4.5" rx="2.2" />
							<circle class="gear" cx="52" cy="98.7" r="4.2" /><circle class="gear" cx="68" cy="98.7" r="4.2" /></g></g></g>
			</g>
		</svg>
	{:else}
		<svg class="fig e" viewBox="0 0 120 170" aria-hidden="true">
			<mask id={biteId} maskUnits="userSpaceOnUse" x="51" y="95" width="19" height="20">
				<rect x="51" y="95" width="19" height="20" fill="#fff" />
				<circle cx="56.1" cy="99.8" r="3.9" fill="#000" />
			</mask>
			<ellipse class="shadow" cx="60" cy="162" rx="26" ry="6" />
			<g class="body">
				<g class="th th-b back"><rect class="skin" x="55.5" y="96" width="9" height="28" rx="4.5" />
					<g class="sh sh-b"><rect class="skin" x="56.25" y="124" width="7.5" height="28" rx="3.75" />
						<rect class="shoe" x="55" y="149" width="13" height="6" rx="3" /></g></g>
				<g class="ua ua-b back"><rect class="skin" x="56.5" y="52" width="7" height="24" rx="3.5" />
					<g class="fa fa-b"><rect class="skin" x="56.75" y="76" width="6.5" height="22" rx="3.25" />
						<circle class="skin" cx="60" cy="99" r="3.6" /></g></g>
				<g class="core">
					<rect class="skin" x="52" y="48" width="16" height="50" rx="8" />
					<rect class="skin" x="56.5" y="42" width="7" height="8" rx="3" />
					<g class="nod"><circle class="skin" cx="60" cy="31" r="13" /></g>
				</g>
				<g class="th th-f"><rect class="skin" x="55.5" y="96" width="9" height="28" rx="4.5" />
					<g class="sh sh-f"><rect class="skin" x="56.25" y="124" width="7.5" height="28" rx="3.75" />
						<rect class="shoe" x="57" y="149" width="13" height="6" rx="3" /></g></g>
				<g class="ua ua-f"><rect class="skin" x="56.5" y="52" width="7" height="24" rx="3.5" />
					<g class="fa fa-f"><rect class="skin" x="56.75" y="76" width="6.5" height="22" rx="3.25" />
						<circle class="skin" cx="60" cy="98" r="3.6" />
						<g class="apple">
							<rect x="59.2" y="98" width="1.6" height="4" rx=".8" fill="#7C5A3A" />
							<ellipse cx="64" cy="99.5" rx="3" ry="1.5" fill="#4FB477" transform="rotate(26 64 99.5)" />
							<circle cx="60" cy="105" r="6.3" fill="#FF6B5B" mask="url(#{biteId})" />
							<ellipse cx="62.6" cy="106.6" rx="1.6" ry="2.2" fill="#FF8C7E" opacity=".7" />
						</g></g></g>
			</g>
		</svg>
	{/if}
	<span class="sr-only">{label ?? m('shell.loading')}</span>
</span>

<style>
	.activity-loader {
		--c: var(--color-primary);
		display: inline-flex;
		align-items: center;
		justify-content: center;
	}
	.fig {
		width: var(--sz);
		height: auto;
		overflow: visible;
	}

	/* ---- figure rig (shared) ---- */
	.fig .skin { fill: var(--c); }
	.fig .shoe { fill: color-mix(in srgb, var(--c) 55%, #000); }
	.fig .gear { fill: color-mix(in srgb, var(--c) 62%, #fff); }
	.fig .shadow { fill: var(--c); opacity: .16; }
	.fig .back { opacity: .5; }

	.ua, .fa, .th, .sh { transform-box: fill-box; transform-origin: 50% 0; }
	.nod { transform-box: fill-box; transform-origin: 50% 100%; }

	/* ---- RUN ---- */
	.r { --d: .72s; }
	.r .lean { transform-box: view-box; transform-origin: 60px 150px; transform: rotate(9deg); }
	.r .body { animation: r-bob calc(var(--d) / 2) ease-in-out infinite; }
	.r .th-f { animation: r-thigh var(--d) linear infinite; }
	.r .sh-f { animation: r-shin var(--d) linear infinite; }
	.r .th-b { animation: r-thigh var(--d) linear infinite; animation-delay: calc(var(--d) / -2); }
	.r .sh-b { animation: r-shin var(--d) linear infinite; animation-delay: calc(var(--d) / -2); }
	.r .ua-b { animation: r-ua var(--d) ease-in-out infinite; }
	.r .fa-b { animation: r-fa var(--d) ease-in-out infinite; }
	.r .ua-f { animation: r-ua var(--d) ease-in-out infinite; animation-delay: calc(var(--d) / -2); }
	.r .fa-f { animation: r-fa var(--d) ease-in-out infinite; animation-delay: calc(var(--d) / -2); }
	@keyframes r-bob { 0%, 100% { transform: translateY(1px); } 50% { transform: translateY(-11px); } }
	@keyframes r-thigh { 0% { transform: rotate(-22deg); } 25% { transform: rotate(6deg); } 50% { transform: rotate(34deg); } 75% { transform: rotate(-30deg); } 100% { transform: rotate(-22deg); } }
	@keyframes r-shin { 0% { transform: rotate(16deg); } 22% { transform: rotate(5deg); } 50% { transform: rotate(14deg); } 74% { transform: rotate(112deg); } 100% { transform: rotate(16deg); } }
	@keyframes r-ua { 0% { transform: rotate(30deg); } 50% { transform: rotate(-26deg); } 100% { transform: rotate(30deg); } }
	@keyframes r-fa { 0% { transform: rotate(-102deg); } 50% { transform: rotate(-120deg); } 100% { transform: rotate(-102deg); } }

	/* ---- TRAIN ---- */
	.t { --d: 1.05s; }
	.t .th-f { transform: rotate(5deg); } .t .th-b { transform: rotate(-6deg); }
	.t .sh-f { transform: rotate(-4deg); } .t .sh-b { transform: rotate(4deg); }
	.t .ua-f, .t .ua-b { transform: rotate(7deg); }
	.t .fa-f { animation: t-curl var(--d) ease-in-out infinite; }
	.t .fa-b { animation: t-curl var(--d) ease-in-out infinite; animation-delay: calc(var(--d) / -2); }
	.t .body { animation: t-effort var(--d) ease-in-out infinite; }
	@keyframes t-curl { 0% { transform: rotate(-12deg); } 50% { transform: rotate(-150deg); } 100% { transform: rotate(-12deg); } }
	@keyframes t-effort { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-2px); } }

	/* ---- FUEL ---- */
	.e { --d: 1.5s; }
	.e .th-f { transform: rotate(6deg); } .e .th-b { transform: rotate(-7deg); }
	.e .sh-f { transform: rotate(-5deg); } .e .sh-b { transform: rotate(5deg); }
	.e .ua-b { transform: rotate(-3deg); } .e .fa-b { transform: rotate(-12deg); }
	.e .ua-f { animation: e-uparm var(--d) ease-in-out infinite; }
	.e .fa-f { animation: e-eat var(--d) ease-in-out infinite; }
	.e .nod { animation: e-nod var(--d) ease-in-out infinite; }
	@keyframes e-uparm { 0% { transform: rotate(-6deg); } 34% { transform: rotate(-30deg); } 72% { transform: rotate(-30deg); } 100% { transform: rotate(-6deg); } }
	@keyframes e-eat { 0% { transform: rotate(-18deg); } 34% { transform: rotate(-150deg); } 72% { transform: rotate(-150deg); } 100% { transform: rotate(-18deg); } }
	@keyframes e-nod { 0%, 28%, 100% { transform: rotate(0); } 38%, 72% { transform: rotate(8deg); } }
	.e .apple { transform-box: view-box; transform-origin: 60px 105px; animation: e-apple var(--d) ease-in-out infinite; }
	@keyframes e-apple { 0% { transform: rotate(24deg); } 34% { transform: rotate(180deg); } 72% { transform: rotate(180deg); } 100% { transform: rotate(24deg); } }

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (prefers-reduced-motion: reduce) {
		.activity-loader :global(*) { animation: none !important; }
	}
</style>
