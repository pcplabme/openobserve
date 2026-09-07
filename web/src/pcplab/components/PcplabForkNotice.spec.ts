// Copyright 2026 PCPLAB
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import { describe, it, expect, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createStore, type Store } from "vuex";

import i18n from "@/locales";
import PcplabForkNotice from "./PcplabForkNotice.vue";
import OCard from "@/lib/core/Card/OCard.vue";
import OCardSection from "@/lib/core/Card/OCardSection.vue";
import OText from "@/lib/core/Typography/OText.vue";
import OCode from "@/lib/core/Code/OCode.vue";
import OIcon from "@/lib/core/Icon/OIcon.vue";
import OTag from "@/lib/core/Badge/OTag.vue";

interface FullFork {
  distribution: string;
  release_channel: "development" | "release-candidate" | "release";
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

const RELEASE_SHA = "0123456789abcdef0123456789abcdef01234567";

function makeFork(overrides: Partial<FullFork> = {}): FullFork {
  return {
    distribution: "PCPLAB OpenObserve OSS fork",
    release_channel: "development",
    company_release: null,
    fork_sha: null,
    upstream_repository: "https://github.com/openobserve/openobserve",
    upstream_source_version: "0.93.0",
    upstream_base_sha: "a1b2c3d4e5f6789012345678901234567890abcd",
    upstream_base_type: "main-development",
    upstream_security_patch_shas: "",
    upstream_security_advisories: "",
    build_timestamp: null,
    docker_image: null,
    license: "AGPL-3.0",
    source: null,
    ...overrides,
  };
}

function makeRelease(overrides: Partial<FullFork> = {}): FullFork {
  return makeFork({
    release_channel: "release",
    company_release: "v0.93.0-pcplab.1",
    fork_sha: RELEASE_SHA,
    build_timestamp: "2026-09-07T14:00:00Z",
    docker_image: "patcharp/openobserve:0.93.0-pcplab.1",
    source: `https://github.com/pcplabme/openobserve/tree/${RELEASE_SHA}`,
    ...overrides,
  });
}

function makeStore(fork: FullFork | null): Store<{ zoConfig: { pcplab_fork?: FullFork | null } }> {
  return createStore({
    state: {
      zoConfig: { pcplab_fork: fork },
    },
  });
}

function mountNotice(fork: FullFork | null) {
  return mount(PcplabForkNotice, {
    global: {
      plugins: [i18n, makeStore(fork)],
      components: { OCard, OCardSection, OText, OCode, OIcon, OTag },
    },
  });
}

describe("PcplabForkNotice", () => {
  beforeEach(() => {
    // explicit anchor so each test gets a fresh i18n-binding cycle
    i18n.global.locale.value = "en-US";
  });

  describe("visibility", () => {
    it("hides when pcplab_fork is absent from zoConfig", () => {
      const wrapper = mountNotice(null);
      expect(wrapper.find('[data-test="pcplab-fork-notice-card"]').exists()).toBe(false);
    });

    it("renders once pcplab_fork is present", () => {
      const wrapper = mountNotice(makeFork());
      expect(wrapper.find('[data-test="pcplab-fork-notice-card"]').exists()).toBe(true);
    });

    it("renders once distribution is present (auth-gated identity row)", () => {
      const wrapper = mountNotice(makeFork());
      expect(wrapper.find('[data-test="pcplab-fork-notice-distribution"]').exists()).toBe(true);
    });
  });

  describe("release channel", () => {
    it("renders a 'Development' tag when release_channel is development", () => {
      const wrapper = mountNotice(makeFork({ release_channel: "development" }));
      const tag = wrapper.find('[data-test="pcplab-fork-notice-channel-tag"]');
      expect(tag.exists()).toBe(true);
      expect(tag.text()).toBe("Development");
      expect(wrapper.find('[data-test="pcplab-fork-notice-release-channel"]').text()).toBe(
        "Development",
      );
    });

    it("renders a 'Release Candidate' tag when release_channel is release-candidate", () => {
      const wrapper = mountNotice(
        makeRelease({
          release_channel: "release-candidate",
          company_release: "v0.93.0-pcplab.1.rc.1",
          docker_image: "patcharp/openobserve:0.93.0-pcplab.1.rc.1",
        }),
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-channel-tag"]').text()).toBe(
        "Release Candidate",
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-release-channel"]').text()).toBe(
        "Release Candidate",
      );
    });

    it("renders a 'Release' tag when release_channel is release", () => {
      const wrapper = mountNotice(makeRelease());
      expect(wrapper.find('[data-test="pcplab-fork-notice-channel-tag"]').text()).toBe("Release");
      expect(wrapper.find('[data-test="pcplab-fork-notice-release-channel"]').text()).toBe(
        "Release",
      );
    });
  });

  describe("development fallback / nulls", () => {
    it("shows the empty-state hint when company_release is null", () => {
      const wrapper = mountNotice(
        makeFork({ release_channel: "development", company_release: null }),
      );
      const cell = wrapper.find('[data-test="pcplab-fork-notice-company-release"]');
      expect(cell.exists()).toBe(true);
      expect(cell.text()).toBe("No company release pinned");
    });

    it("renders the company_release value when present", () => {
      const wrapper = mountNotice(makeRelease());
      const cell = wrapper.find('[data-test="pcplab-fork-notice-company-release"]');
      expect(cell.text()).toBe("v0.93.0-pcplab.1");
    });

    it("omits the build-timestamp row when build_timestamp is null", () => {
      const wrapper = mountNotice(
        makeFork({ release_channel: "development", build_timestamp: null }),
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-build-timestamp"]').exists()).toBe(false);
    });

    it("renders the build timestamp when it is present", () => {
      const wrapper = mountNotice(
        makeFork({
          release_channel: "development",
          build_timestamp: "2026-01-15T08:30:00Z",
        }),
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-build-timestamp"]').text()).toBe(
        "2026-01-15T08:30:00Z",
      );
    });

    it("renders the immutable Docker image for a release", () => {
      const wrapper = mountNotice(makeRelease());
      expect(wrapper.find('[data-test="pcplab-fork-notice-docker-image"]').text()).toBe(
        "patcharp/openobserve:0.93.0-pcplab.1",
      );
    });
  });

  describe("fork SHA source link", () => {
    it("renders only the SHA code when fork_sha is null", () => {
      const wrapper = mountNotice(makeFork({ fork_sha: null }));
      expect(wrapper.find('[data-test="pcplab-fork-notice-fork-sha"]').exists()).toBe(true);
      const link = wrapper.find('[data-test="pcplab-fork-notice-fork-sha-link"]');
      expect(link.exists()).toBe(false);
      expect(wrapper.find('[data-test="pcplab-fork-notice-fork-sha"]').text()).toBe(
        "Fork commit not recorded",
      );
    });

    it("renders only the SHA code when source URL is missing", () => {
      const sha = "0123456789abcdef0123456789abcdef01234567";
      const wrapper = mountNotice(makeFork({ fork_sha: sha, source: null }));
      const link = wrapper.find('[data-test="pcplab-fork-notice-fork-sha-link"]');
      expect(link.exists()).toBe(false);
      // commit is still rendered (just un-linked)
      expect(wrapper.find('[data-test="pcplab-fork-notice-fork-sha"]').text()).toContain(sha);
    });

    it("renders the backend-provided commit-pinned source link", () => {
      const sha = RELEASE_SHA;
      const source = `https://github.com/pcplabme/openobserve/tree/${sha}`;
      const wrapper = mountNotice(makeRelease());
      const link = wrapper.find('[data-test="pcplab-fork-notice-fork-sha-link"]');
      expect(link.exists()).toBe(true);
      expect(link.attributes("href")).toBe(source);
      expect(link.attributes("target")).toBe("_blank");
    });

    it("rejects a mutable source URL", () => {
      const wrapper = mountNotice(
        makeRelease({
          source: "https://github.com/pcplabme/openobserve/tree/main",
        }),
      );
      const link = wrapper.find('[data-test="pcplab-fork-notice-fork-sha-link"]');
      expect(link.exists()).toBe(false);
    });

    it("rejects a commit-pinned URL for a different fork SHA", () => {
      const wrapper = mountNotice(
        makeRelease({
          source:
            "https://github.com/pcplabme/openobserve/tree/ffffffffffffffffffffffffffffffffffffffff",
        }),
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-fork-sha-link"]').exists()).toBe(false);
      expect(wrapper.find('[data-test="pcplab-fork-notice-source"]').exists()).toBe(false);
    });
  });

  describe("conditional security metadata", () => {
    it("omits the security-patch SHAs row when the backend supplies an empty string", () => {
      const wrapper = mountNotice(
        makeFork({ upstream_security_patch_shas: "", upstream_security_advisories: "" }),
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-security"]').exists()).toBe(
        false,
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-advisories"]').exists()).toBe(
        false,
      );
    });

    it("renders the security-patch SHAs when provided", () => {
      const shas =
        "0123456789abcdef0123456789abcdef01234567,89abcdef0123456789abcdef0123456789abcdef";
      const wrapper = mountNotice(makeFork({ upstream_security_patch_shas: shas }));
      const row = wrapper.find('[data-test="pcplab-fork-notice-upstream-security"]');
      expect(row.exists()).toBe(true);
      expect(row.text()).toContain("0123456789abcdef");
    });

    it("renders the upstream advisories when provided", () => {
      const advisories = "GHSA-abcd-1234-efgh";
      const wrapper = mountNotice(makeFork({ upstream_security_advisories: advisories }));
      const row = wrapper.find('[data-test="pcplab-fork-notice-upstream-advisories"]');
      expect(row.exists()).toBe(true);
      expect(row.text()).toContain("GHSA-abcd-1234-efgh");
    });

    it("ignores whitespace-only security metadata", () => {
      const wrapper = mountNotice(
        makeFork({ upstream_security_patch_shas: "   ", upstream_security_advisories: "   " }),
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-security"]').exists()).toBe(
        false,
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-advisories"]').exists()).toBe(
        false,
      );
    });
  });

  describe("always-present metadata", () => {
    it("renders the upstream repository, source version, base SHA, base type, license, and source URL", () => {
      const fork = makeRelease({
        upstream_repository: "https://github.com/openobserve/openobserve",
        upstream_source_version: "0.93.0",
        upstream_base_sha: "deadbeefcafebabe0123456789abcdef01234567",
        upstream_base_type: "main-development",
        license: "AGPL-3.0",
        source:
          "https://github.com/pcplabme/openobserve/tree/0123456789abcdef0123456789abcdef01234567",
      });
      const wrapper = mountNotice(fork);
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-repository"]').text()).toBe(
        "https://github.com/openobserve/openobserve",
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-source-version"]').text()).toBe(
        "0.93.0",
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-base-sha"]').text()).toContain(
        "deadbeefcafebabe",
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-base-type"]').text()).toBe(
        "main-development",
      );
      expect(wrapper.find('[data-test="pcplab-fork-notice-license"]').text()).toBe("AGPL-3.0");
      expect(wrapper.find('[data-test="pcplab-fork-notice-source"]').text()).toBe(
        "https://github.com/pcplabme/openobserve/tree/0123456789abcdef0123456789abcdef01234567",
      );
    });

    it.each(["release-tag", "security-cherry-pick"])(
      "renders the %s base type verbatim",
      (baseType) => {
        const wrapper = mountNotice(makeFork({ upstream_base_type: baseType }));
        expect(wrapper.find('[data-test="pcplab-fork-notice-upstream-base-type"]').text()).toBe(
          baseType,
        );
      },
    );
  });
});
