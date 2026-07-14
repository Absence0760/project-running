<script lang="ts">
	const lastUpdated = '2026-07-14';
</script>

<svelte:head>
	<title>Consumer Health Data Privacy Policy — Threkir</title>
	<meta
		name="description"
		content="How Threkir collects, uses, and shares consumer health data, and the rights of Washington residents under the My Health My Data Act."
	/>
</svelte:head>

<div class="legal-page">
	<h1>Consumer Health Data Privacy Policy</h1>
	<p class="lead">
		This notice supplements our <a href="/privacy">Privacy Policy</a> for residents of Washington
		State (under the My Health My Data Act) and of other US states with consumer-health-data laws.
		It describes the health data Threkir collects, why, who can receive it, and your rights.
	</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Consumer health data we collect</h2>
	<ul>
		<li><strong>Heart rate</strong>, when you pair a sensor or import from a connected service.</li>
		<li><strong>Body measurements</strong>: height, body-weight entries, and activity level, if you enter them.</li>
		<li><strong>Nutrition data</strong>: food-log entries, macro targets, and hydration amounts, if you use the nutrition features.</li>
		<li><strong>Exercise data</strong>: runs, gym workouts, step counts, and derived fitness metrics.</li>
		<li><strong>Precise location</strong>: GPS tracks of your activities and, if you enable it, live location during a run.</li>
		<li><strong>Race medical data</strong>: at organised events using medical weigh-ins, your weight and any medical hold or note recorded by event staff (scrubbed after 90 days).</li>
	</ul>

	<h2>2. Why we collect it (and consent)</h2>
	<p>
		We collect this data only to provide the features you use — recording and displaying your
		activities, computing training and nutrition targets, powering the AI Coach when you open it,
		and running the safety features you enable. Health-related categories (heart rate, body
		measurements, nutrition) are gated behind an explicit in-app consent you can withdraw at any
		time in Settings → Account. We do not use consumer health data for advertising, and we
		<strong>do not sell consumer health data</strong> — so no "sale" authorization is ever
		requested.
	</p>

	<h2>3. Who can receive it</h2>
	<p>
		Consumer health data is shared only with the processors we use to run the service (our
		database and hosting providers, and the AI provider when you use the Coach) — the full list,
		with what each receives, is in the
		<a href="/privacy#sub-processors">Privacy Policy's sub-processor section</a>. Other users see your activity data only according to your sharing settings, and
		your tracks are clipped around your privacy zones before anyone else sees them. We do not
		share consumer health data with advertisers or data brokers.
	</p>

	<h2>4. Your rights</h2>
	<ul>
		<li><strong>Access</strong>: Settings → Export your data gives you a machine-readable copy, including all health data.</li>
		<li><strong>Withdraw consent</strong>: Settings → Account → health-data consent; withdrawal blocks further collection and processing of the consented categories.</li>
		<li><strong>Delete</strong>: delete individual entries (runs, weights, food logs) in-app, or the whole account via Settings → Delete account. Deletion cascades through our systems and our processors on the schedule in the Privacy Policy.</li>
		<li><strong>Appeal</strong>: if we decline a request, you may appeal by replying to our decision or emailing <a href="mailto:privacy@threkir.com">privacy@threkir.com</a> with "Appeal" in the subject. If the appeal fails, Washington residents may contact the <a href="https://www.atg.wa.gov/" target="_blank" rel="noopener noreferrer">Washington Attorney General</a>.</li>
	</ul>

	<h2>5. Contact</h2>
	<p>
		<a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
		line-height: 1.6;
	}
	h1 {
		margin-top: 0;
	}
	h2 {
		margin-top: var(--space-2xl);
		font-size: 1.25rem;
	}
	.lead {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}
	.meta {
		color: var(--color-text-tertiary);
		font-size: 0.875rem;
		margin-bottom: var(--space-2xl);
	}
	ul {
		padding-inline-start: 1.25rem;
	}
	li {
		margin-bottom: var(--space-xs);
	}
</style>
