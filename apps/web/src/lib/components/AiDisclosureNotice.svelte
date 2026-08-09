<script lang="ts">
	// The AI-processing disclosure the user accepts (GDPR Art 6(1)(a)).
	// One copy, two hosts: the /coach first-use dialog and the
	// Settings → Account section where an existing user accepts a widened
	// version. Keeping it here is what stops the two surfaces describing
	// different processing while writing the same consent record.
	//
	// The strings keep their `coachPage.consent*` keys — the Coach remains
	// the surface that first presents them, and renaming a shipped key set
	// across six catalogues buys nothing behavioural.
	import { m } from '$lib/i18n/store.svelte';
</script>

<p>
	{m('coachPage.consentIntroPrefix')}<strong>Anthropic</strong>{m('coachPage.consentIntroSuffix')}
</p>
<ul>
	<li>{m('coachPage.consentBulletProfile')}</li>
	<li>{m('coachPage.consentBulletRuns')}</li>
	<li>{m('coachPage.consentBulletPlan')}</li>
	<li>{m('coachPage.consentBulletMessages')}</li>
	<li>{m('coachPage.consentBulletRoutes')}</li>
</ul>
<p>
	{m('coachPage.consentTermsPrefix')}<a href="/privacy">{m('coachPage.consentPrivacyLink')}</a>{m(
		'coachPage.consentTermsSuffix',
	)}
</p>
