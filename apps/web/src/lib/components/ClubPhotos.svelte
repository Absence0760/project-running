<script lang="ts">
	import { onMount } from 'svelte';
	import {
		fetchClubPhotosWithError,
		addClubPhoto,
		deleteClubPhoto,
		updateClubPhotoCaption,
		type ClubPhoto,
	} from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';
	import { safeImageSrc } from '$lib/util/safe_image_src';

	interface Props {
		clubId: string;
		// Any active member may upload.
		canUpload?: boolean;
		// Club owner / admin may delete anyone's photo (moderation).
		canModerate?: boolean;
		wrapperClass?: string;
	}
	let { clubId, canUpload = false, canModerate = false, wrapperClass = 'card' }: Props = $props();

	let photos = $state<ClubPhoto[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let uploading = $state(false);
	let pendingCaption = $state('');
	let pendingFile = $state<File | null>(null);
	let lightbox = $state<ClubPhoto | null>(null);
	let confirmDelete = $state<ClubPhoto | null>(null);
	let editingId = $state<string | null>(null);
	let editingCaption = $state('');
	let fileInput: HTMLInputElement | undefined = $state();

	function isOwner(p: ClubPhoto): boolean {
		return auth.user?.id === p.owner_id;
	}
	function canDelete(p: ClubPhoto): boolean {
		return canModerate || isOwner(p);
	}

	async function load() {
		loading = true;
		loadError = null;
		try {
			const res = await fetchClubPhotosWithError(clubId);
			if (res.error) {
				loadError = res.error;
				return;
			}
			photos = res.photos;
		} catch (e) {
			loadError = e instanceof Error ? e.message : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function pickFile() {
		fileInput?.click();
	}

	function onFileChange(e: Event) {
		const target = e.currentTarget as HTMLInputElement;
		const f = target.files?.[0] ?? null;
		pendingFile = f;
	}

	async function uploadPending() {
		if (!pendingFile) return;
		uploading = true;
		try {
			const photo = await addClubPhoto({
				club_id: clubId,
				file: pendingFile,
				caption: pendingCaption,
			});
			photos = [...photos, photo];
			pendingFile = null;
			pendingCaption = '';
			if (fileInput) fileInput.value = '';
		} catch (e: any) {
			showToast(e?.message ?? m('clubPhotos.uploadFailed'), 'error');
		} finally {
			uploading = false;
		}
	}

	function cancelPending() {
		pendingFile = null;
		pendingCaption = '';
		if (fileInput) fileInput.value = '';
	}

	async function doDelete() {
		const target = confirmDelete;
		if (!target) return;
		confirmDelete = null;
		try {
			await deleteClubPhoto(target.id);
			photos = photos.filter((p) => p.id !== target.id);
			if (lightbox?.id === target.id) lightbox = null;
		} catch (e: any) {
			showToast(e?.message ?? m('clubPhotos.deleteFailed'), 'error');
		}
	}

	function startEdit(p: ClubPhoto) {
		editingId = p.id;
		editingCaption = p.caption ?? '';
	}

	async function saveCaption() {
		if (!editingId) return;
		const id = editingId;
		const next = editingCaption.trim() || null;
		editingId = null;
		try {
			await updateClubPhotoCaption(id, next);
			photos = photos.map((p) => (p.id === id ? { ...p, caption: next } : p));
		} catch (e: any) {
			showToast(e?.message ?? m('clubPhotos.captionUpdateFailed'), 'error');
		}
	}
</script>

{#if canUpload || loading || photos.length > 0 || loadError}
<section class={wrapperClass}>
<div class="photos">
	<header class="hd">
		<h3>
			<span class="material-symbols">photo_library</span>
			{m('clubPhotos.heading')}
			{#if photos.length > 0}<span class="muted">({photos.length})</span>{/if}
		</h3>
		{#if canUpload}
			<button type="button" class="btn btn-secondary btn-sm" onclick={pickFile}>
				<span class="material-symbols">add_photo_alternate</span>
				{m('clubPhotos.addPhoto')}
			</button>
		{/if}
	</header>

	<input
		bind:this={fileInput}
		type="file"
		accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
		hidden
		onchange={onFileChange}
	/>

	{#if pendingFile && canUpload}
		<div class="pending">
			<div class="pending-thumb">
				<img src={safeImageSrc(URL.createObjectURL(pendingFile), { allowBlob: true })} alt="" />
			</div>
			<div class="pending-fields">
				<input
					type="text"
					placeholder={m('clubPhotos.captionPlaceholder')}
					maxlength="280"
					bind:value={pendingCaption}
					disabled={uploading}
				/>
				<div class="pending-actions">
					<button class="btn btn-secondary btn-sm" type="button" onclick={cancelPending} disabled={uploading}>
						{m('clubPhotos.cancel')}
					</button>
					<button class="btn btn-primary btn-sm" type="button" onclick={uploadPending} disabled={uploading}>
						{uploading ? m('clubPhotos.uploading') : m('clubPhotos.upload')}
					</button>
				</div>
			</div>
		</div>
	{/if}

	{#if loading}
		<p class="muted">{m('clubPhotos.loadingPhotos')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('socialClubs.loadErrorText')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline btn-sm" onclick={load}>{m('socialClubs.retry')}</button>
		</div>
	{:else if photos.length === 0 && !canUpload}
		<p class="muted">{m('clubPhotos.noPhotos')}</p>
	{:else if photos.length > 0}
		<div class="grid">
			{#each photos as p (p.id)}
				<figure class="tile">
					<button class="tile-img" type="button" onclick={() => (lightbox = p)} aria-label={m('clubPhotos.openPhoto')}>
						<img src={safeImageSrc(p.thumbUrl ?? p.url)} alt={p.caption ?? ''} loading="lazy" />
					</button>
					{#if editingId === p.id}
						<form
							class="caption-edit"
							onsubmit={(e) => {
								e.preventDefault();
								saveCaption();
							}}
						>
							<input
								type="text"
								bind:value={editingCaption}
								maxlength="280"
								placeholder={m('clubPhotos.captionEditPlaceholder')}
							/>
							<button class="btn btn-primary btn-sm" type="submit">{m('clubPhotos.save')}</button>
							<button class="btn btn-secondary btn-sm" type="button" onclick={() => (editingId = null)}>
								{m('clubPhotos.cancel')}
							</button>
						</form>
					{:else if p.caption}
						<figcaption>{p.caption}</figcaption>
					{/if}
					{#if isOwner(p) || canDelete(p)}
						<div class="tile-actions">
							{#if isOwner(p) && editingId !== p.id}
								<button
									type="button"
									class="icon-btn"
									aria-label={m('clubPhotos.editCaption')}
									title={m('clubPhotos.editCaption')}
									onclick={() => startEdit(p)}
								>
									<span class="material-symbols">edit</span>
								</button>
							{/if}
							{#if canDelete(p)}
								<button
									type="button"
									class="icon-btn"
									aria-label={m('clubPhotos.deletePhoto')}
									title={m('clubPhotos.deletePhoto')}
									onclick={() => (confirmDelete = p)}
								>
									<span class="material-symbols">delete</span>
								</button>
							{/if}
						</div>
					{/if}
				</figure>
			{/each}
		</div>
	{/if}
</div>
</section>
{/if}

{#if lightbox}
	<button
		class="lightbox"
		type="button"
		aria-label={m('clubPhotos.close')}
		onclick={() => (lightbox = null)}
	>
		<img src={safeImageSrc(lightbox.url)} alt={lightbox.caption ?? ''} />
		{#if lightbox.caption}
			<div class="lightbox-caption">{lightbox.caption}</div>
		{/if}
	</button>
{/if}

<ConfirmDialog
	open={confirmDelete != null}
	title={m('clubPhotos.deleteConfirmTitle')}
	message={m('clubPhotos.deleteConfirmMessage')}
	confirmLabel={m('clubPhotos.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmDelete = null)}
/>

<style>
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}

	.photos {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.hd {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
	}

	.hd h3 {
		margin: 0;
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 1rem;
	}

	.hd h3 .material-symbols {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}

	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		font-weight: 500;
	}

	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.3rem;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
		gap: var(--space-sm);
	}

	.tile {
		position: relative;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}

	.tile-img {
		display: block;
		width: 100%;
		aspect-ratio: 1 / 1;
		padding: 0;
		border: none;
		border-radius: var(--radius-md);
		overflow: hidden;
		background: var(--color-surface);
		cursor: zoom-in;
	}

	.tile-img img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}

	figcaption {
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		line-height: 1.35;
		white-space: pre-wrap;
		word-break: break-word;
	}

	.caption-edit {
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
	}

	.caption-edit input {
		flex: 1 1 100%;
		padding: 0.35rem 0.55rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-size: 0.85rem;
	}

	.tile-actions {
		position: absolute;
		top: 0.4rem;
		inset-inline-end: 0.4rem;
		display: flex;
		gap: 0.25rem;
		opacity: 0;
		transition: opacity var(--transition-fast);
	}

	.tile:hover .tile-actions,
	.tile:focus-within .tile-actions {
		opacity: 1;
	}

	.icon-btn {
		display: inline-grid;
		place-items: center;
		width: 1.85rem;
		height: 1.85rem;
		border: none;
		border-radius: 50%;
		background: rgba(0, 0, 0, 0.55);
		color: white;
		cursor: pointer;
	}

	.icon-btn:hover {
		background: rgba(0, 0, 0, 0.75);
	}

	.icon-btn .material-symbols {
		font-size: 1.05rem;
	}

	.pending {
		display: flex;
		gap: var(--space-md);
		padding: var(--space-md);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
	}

	.pending-thumb {
		flex-shrink: 0;
		width: 6rem;
		height: 6rem;
		border-radius: var(--radius-sm);
		overflow: hidden;
		background: var(--color-bg);
	}

	.pending-thumb img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}

	.pending-fields {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.pending-fields input {
		padding: 0.4rem 0.65rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		font-size: 0.9rem;
	}

	.pending-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}

	.lightbox {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.85);
		display: grid;
		place-items: center;
		padding: var(--space-lg);
		border: none;
		cursor: zoom-out;
		z-index: 1000;
	}

	.lightbox img {
		max-width: min(96vw, 1200px);
		max-height: 88vh;
		object-fit: contain;
		border-radius: var(--radius-md);
	}

	.lightbox-caption {
		position: absolute;
		bottom: var(--space-lg);
		left: 50%;
		transform: translateX(-50%);
		max-width: 80%;
		padding: 0.5rem 0.85rem;
		background: rgba(0, 0, 0, 0.6);
		color: white;
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		text-align: center;
	}
</style>
