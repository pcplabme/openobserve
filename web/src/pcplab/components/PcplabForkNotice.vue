<!-- Copyright 2026 PCPLAB

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
-->

<script setup lang="ts">
import { computed } from "vue";
import { useStore } from "vuex";

import { raw, useI18nTyped } from "@/types/i18n";
import OCard from "@/lib/core/Card/OCard.vue";
import OCardSection from "@/lib/core/Card/OCardSection.vue";
import OText from "@/lib/core/Typography/OText.vue";
import OCode from "@/lib/core/Code/OCode.vue";
import OIcon from "@/lib/core/Icon/OIcon.vue";
import OTag from "@/lib/core/Badge/OTag.vue";

interface PcplabForkMetadata {
  distribution: string;
  release_channel: "development" | "release-candidate" | "release" | string;
  company_release: string | null;
  fork_sha: string | null;
  upstream_repository: string;
  upstream_source_version: string;
  upstream_base_sha: string;
  upstream_base_type: string;
  upstream_security_patch_shas: string;
  upstream_security_advisories: string;
  build_timestamp: string | null;
  docker_image: string | null;
  license: string;
  source: string | null;
}

const store = useStore();
const { t } = useI18nTyped();

const fork = computed<PcplabForkMetadata | null>(
  () => (store.state.zoConfig?.pcplab_fork ?? null) as PcplabForkMetadata | null,
);

// Render only when the backend has emitted fork metadata. The presence of
// `pcplab_fork` on the runtime config is the auth-gated signal.
const isVisible = computed(() => fork.value !== null && !!fork.value.distribution);

const channelVariant = computed(() => {
  switch (fork.value?.release_channel) {
    case "release":
      return "success-soft";
    case "release-candidate":
      return "info-outline";
    case "development":
      return "warning-soft";
    default:
      return "default-soft";
  }
});

const channelLabelKey = computed(() => {
  switch (fork.value?.release_channel) {
    case "release":
      return "about.pcplab_fork_release_channel_release" as const;
    case "release-candidate":
      return "about.pcplab_fork_release_channel_release_candidate" as const;
    case "development":
      return "about.pcplab_fork_release_channel_development" as const;
    default:
      return null;
  }
});

const channelLabel = computed(() =>
  channelLabelKey.value ? t(channelLabelKey.value) : raw(String(fork.value?.release_channel ?? "")),
);

const distribution = computed(() => fork.value?.distribution ?? "");
const companyRelease = computed(() => fork.value?.company_release ?? null);
const forkSha = computed(() => fork.value?.fork_sha ?? null);
const buildTimestamp = computed(() => fork.value?.build_timestamp ?? null);
const dockerImage = computed(() => fork.value?.docker_image ?? null);
const license = computed(() => fork.value?.license ?? "");
const source = computed(() => fork.value?.source?.trim() ?? "");

const upstreamRepository = computed(() => fork.value?.upstream_repository ?? "");
const upstreamSourceVersion = computed(() => fork.value?.upstream_source_version ?? "");
const upstreamBaseSha = computed(() => fork.value?.upstream_base_sha ?? "");
const upstreamBaseType = computed(() => fork.value?.upstream_base_type ?? "");

const securityPatchShas = computed(() => fork.value?.upstream_security_patch_shas?.trim() ?? "");
const securityAdvisories = computed(() => fork.value?.upstream_security_advisories?.trim() ?? "");

// The backend emits a commit-pinned corresponding-source URL. Never construct
// or guess a mutable branch URL in the browser.
const forkSourceUrl = computed(() => {
  if (!forkSha.value || !source.value) return null;
  const match = source.value.match(
    /^https:\/\/github\.com\/pcplabme\/openobserve\/tree\/([0-9a-f]{40})$/i,
  );
  if (!match || match[1].toLowerCase() !== forkSha.value.toLowerCase()) {
    return null;
  }
  return source.value;
});
</script>

<template>
  <OCard v-if="isVisible" data-test="pcplab-fork-notice-card" class="bg-card-glass-bg gap-0 p-0">
    <OCardSection
      role="header"
      class="border-border-default gap-3 border-b"
      data-test="pcplab-fork-notice-header"
    >
      <div
        class="rounded-default text-accent bg-card-glass-tint-medium flex h-10 w-10 shrink-0 items-center justify-center"
      >
        <OIcon name="fork-right" size="md" />
      </div>
      <div class="flex min-w-0 flex-1 flex-col gap-0.5">
        <OText variant="section" class="text-accent">
          {{ t("about.pcplab_fork_eyebrow") }}
        </OText>
        <OText variant="page-title" as="h2" class="text-lg font-semibold">
          {{ t("about.pcplab_fork_title") }}
        </OText>
      </div>
      <OTag
        :variant="channelVariant"
        size="sm"
        shape="rounded"
        data-test="pcplab-fork-notice-channel-tag"
      >
        {{ channelLabel }}
      </OTag>
    </OCardSection>

    <OCardSection role="body" class="gap-4" data-test="pcplab-fork-notice-body">
      <OText variant="body" class="text-text-secondary">
        {{ t("about.pcplab_fork_intro") }}
      </OText>

      <div
        class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]"
        data-test="pcplab-fork-notice-grid"
      >
        <!-- Distribution -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_distribution_lbl") }}
        </OText>
        <OText variant="body-strong" class="font-mono" data-test="pcplab-fork-notice-distribution">
          {{ raw(distribution) }}
        </OText>

        <!-- Release channel -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_release_channel_lbl") }}
        </OText>
        <OText variant="body-strong" data-test="pcplab-fork-notice-release-channel">
          {{ channelLabel }}
        </OText>

        <!-- Company release — null falls back to the empty-state hint -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_company_release_lbl") }}
        </OText>
        <div data-test="pcplab-fork-notice-company-release">
          <OText v-if="companyRelease" variant="body-strong" class="font-mono">
            {{ raw(companyRelease) }}
          </OText>
          <OText v-else variant="meta" class="text-text-muted">
            {{ t("about.pcplab_fork_company_release_empty") }}
          </OText>
        </div>

        <!-- Fork SHA — renders a source link only when the backend exposes a URL -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_fork_sha_lbl") }}
        </OText>
        <div data-test="pcplab-fork-notice-fork-sha" class="flex items-center gap-2">
          <template v-if="forkSha">
            <OCode>{{ raw(forkSha) }}</OCode>
            <a
              v-if="forkSourceUrl"
              :href="forkSourceUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="text-text-link hover:border-text-link border-text-link/35 border-b text-sm font-medium no-underline"
              data-test="pcplab-fork-notice-fork-sha-link"
            >
              {{ t("about.pcplab_fork_fork_sha_view_source") }}
            </a>
          </template>
          <template v-else>
            <OText variant="meta" class="text-text-muted">
              {{ t("about.pcplab_fork_fork_sha_empty") }}
            </OText>
          </template>
        </div>

        <!-- Upstream repository -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_upstream_repository_lbl") }}
        </OText>
        <OText variant="mono" data-test="pcplab-fork-notice-upstream-repository">
          {{ raw(upstreamRepository) }}
        </OText>

        <!-- Upstream source version -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_upstream_source_version_lbl") }}
        </OText>
        <OText variant="mono" data-test="pcplab-fork-notice-upstream-source-version">
          {{ raw(upstreamSourceVersion) }}
        </OText>

        <!-- Upstream base SHA -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_upstream_base_sha_lbl") }}
        </OText>
        <OCode data-test="pcplab-fork-notice-upstream-base-sha">{{ raw(upstreamBaseSha) }}</OCode>

        <!-- Upstream base type is a governance enum and must remain verbatim. -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_upstream_base_type_lbl") }}
        </OText>
        <OText variant="body-strong" data-test="pcplab-fork-notice-upstream-base-type">
          {{ raw(upstreamBaseType) }}
        </OText>

        <!-- Security patch SHAs — only shown when backend supplied a non-empty list -->
        <template v-if="securityPatchShas">
          <OText variant="label" class="text-text-secondary uppercase">
            {{ t("about.pcplab_fork_upstream_security_lbl") }}
          </OText>
          <OCode block data-test="pcplab-fork-notice-upstream-security">{{
            raw(securityPatchShas)
          }}</OCode>
        </template>

        <!-- Security advisories — only shown when present -->
        <template v-if="securityAdvisories">
          <OText variant="label" class="text-text-secondary uppercase">
            {{ t("about.pcplab_fork_upstream_advisories_lbl") }}
          </OText>
          <OCode block data-test="pcplab-fork-notice-upstream-advisories">{{
            raw(securityAdvisories)
          }}</OCode>
        </template>

        <!-- Build timestamp — null hides the row -->
        <template v-if="buildTimestamp">
          <OText variant="label" class="text-text-secondary uppercase">
            {{ t("about.pcplab_fork_build_timestamp_lbl") }}
          </OText>
          <OText variant="mono" data-test="pcplab-fork-notice-build-timestamp">
            {{ raw(buildTimestamp) }}
          </OText>
        </template>

        <!-- Immutable Docker image identity — release builds only. -->
        <template v-if="dockerImage">
          <OText variant="label" class="text-text-secondary uppercase">
            {{ t("about.pcplab_fork_docker_image_lbl") }}
          </OText>
          <OCode data-test="pcplab-fork-notice-docker-image">{{ raw(dockerImage) }}</OCode>
        </template>

        <!-- License — always rendered, raw because it's an SPDX identifier -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_license_lbl") }}
        </OText>
        <OText variant="body-strong" class="font-mono" data-test="pcplab-fork-notice-license">
          {{ raw(license) }}
        </OText>

        <!-- Corresponding source — linked only when it is commit-pinned. -->
        <OText variant="label" class="text-text-secondary uppercase">
          {{ t("about.pcplab_fork_source_lbl") }}
        </OText>
        <a
          v-if="forkSourceUrl"
          :href="forkSourceUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="text-text-link hover:border-text-link border-text-link/35 w-fit border-b font-mono text-sm no-underline"
          data-test="pcplab-fork-notice-source"
        >
          {{ raw(source) }}
        </a>
        <OText v-else variant="meta" data-test="pcplab-fork-notice-source-unavailable">
          {{ t("about.pcplab_fork_source_unavailable") }}
        </OText>
      </div>
    </OCardSection>
  </OCard>
</template>
