<main class="account-page">
	<h1>Account</h1>

	<section>
		<h2>Profile</h2>
		<!-- TODO: Display name, avatar, parkrun number -->
	</section>

	<section>
		<h2>Preferences</h2>
		<!-- TODO: Unit preference (km/mi) -->
	</section>

	<section>
		<h2>Data Export</h2>
		<button class="btn">Download all data as GPX</button>
	</section>

	<section class="danger">
		<h2>Danger Zone</h2>
		<button class="btn btn-danger">Delete Account</button>
	</section>
</main>

<style>
	.account-page { max-width: 40rem; margin: 0 auto; padding: 2rem; }
	h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: 2rem; }
	h2 { font-size: 1.125rem; font-weight: 600; margin-bottom: 0.75rem; }
	section { margin-bottom: 1.5rem; }
	.btn {
		padding: 0.5rem 1rem;
		border: 1px solid #e5e5e5;
		border-radius: 0.5rem;
		font-size: 0.875rem;
		cursor: pointer;
		background: white;
	}
	.danger h2 { color: #dc2626; }
	.btn-danger { border-color: #fca5a5; color: #dc2626; }
</style>
