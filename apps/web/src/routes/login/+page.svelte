<script lang="ts">
	function handleGoogleSignIn() {
		// TODO: Supabase Google OAuth
	}

	function handleAppleSignIn() {
		// TODO: Supabase Apple OAuth
	}
</script>

<main class="login">
	<div class="login-card">
		<h1>Sign in to Run App</h1>
		<div class="login-buttons">
			<button onclick={handleGoogleSignIn} class="btn btn-google">
				Continue with Google
			</button>
			<button onclick={handleAppleSignIn} class="btn btn-apple">
				Continue with Apple
			</button>
		</div>
	</div>
</main>

<style>
	.login {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
	}
	.login-card {
		width: 100%;
		max-width: 24rem;
		padding: 2rem;
	}
	h1 { font-size: 1.5rem; text-align: center; margin-bottom: 1.5rem; }
	.login-buttons { display: flex; flex-direction: column; gap: 0.75rem; }
	.btn {
		width: 100%;
		padding: 0.75rem 1rem;
		border-radius: 0.5rem;
		font-size: 1rem;
		cursor: pointer;
		border: 1px solid #ddd;
	}
	.btn-google { background: white; }
	.btn-google:hover { background: #f9f9f9; }
	.btn-apple { background: black; color: white; border-color: black; }
	.btn-apple:hover { opacity: 0.9; }
</style>
