// Copyright 2026 PCPLAB
// SPDX-License-Identifier: AGPL-3.0-or-later

#[cfg(test)]
mod validation;

use serde::Serialize;

/// Immutable fork and upstream provenance compiled into this binary.
#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
pub struct ForkBuildMetadata {
    pub distribution: &'static str,
    pub release_channel: &'static str,
    pub company_release: Option<&'static str>,
    pub fork_sha: Option<&'static str>,
    pub upstream_repository: &'static str,
    pub upstream_source_version: &'static str,
    pub upstream_base_sha: &'static str,
    pub upstream_base_type: &'static str,
    pub upstream_security_patch_shas: &'static str,
    pub upstream_security_advisories: &'static str,
    pub build_timestamp: Option<&'static str>,
    pub docker_image: Option<&'static str>,
    pub license: &'static str,
    pub source: Option<&'static str>,
}

pub fn get() -> ForkBuildMetadata {
    ForkBuildMetadata {
        distribution: env!("PCPLAB_BUILD_DISTRIBUTION"),
        release_channel: env!("PCPLAB_BUILD_RELEASE_CHANNEL"),
        company_release: non_empty(env!("PCPLAB_BUILD_COMPANY_RELEASE")),
        fork_sha: non_empty(env!("PCPLAB_BUILD_FORK_SHA")),
        upstream_repository: env!("PCPLAB_BUILD_UPSTREAM_REPOSITORY"),
        upstream_source_version: env!("PCPLAB_BUILD_UPSTREAM_SOURCE_VERSION"),
        upstream_base_sha: env!("PCPLAB_BUILD_UPSTREAM_BASE_SHA"),
        upstream_base_type: env!("PCPLAB_BUILD_UPSTREAM_BASE_TYPE"),
        upstream_security_patch_shas: env!("PCPLAB_BUILD_UPSTREAM_SECURITY_PATCH_SHAS"),
        upstream_security_advisories: env!("PCPLAB_BUILD_UPSTREAM_SECURITY_ADVISORIES"),
        build_timestamp: non_empty(env!("PCPLAB_BUILD_TIMESTAMP_VALUE")),
        docker_image: non_empty(env!("PCPLAB_BUILD_DOCKER_IMAGE")),
        license: env!("PCPLAB_BUILD_LICENSE"),
        source: non_empty(env!("PCPLAB_BUILD_SOURCE")),
    }
}

fn non_empty(value: &'static str) -> Option<&'static str> {
    (!value.is_empty()).then_some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compiled_metadata_is_honest_for_this_build() {
        let metadata = get();
        assert_eq!(metadata.distribution, "PCPLAB OpenObserve OSS fork");
        assert_eq!(metadata.license, "AGPL-3.0");
        assert_eq!(metadata.upstream_source_version, "0.93.0");
        assert_eq!(metadata.upstream_base_sha.len(), 40);

        if metadata.release_channel == "development" {
            assert!(metadata.company_release.is_none());
            assert!(metadata.build_timestamp.is_none());
            assert!(metadata.docker_image.is_none());
        } else {
            assert!(metadata.company_release.is_some());
            assert!(metadata.fork_sha.is_some());
            assert!(metadata.build_timestamp.is_some());
            let expected_image = format!(
                "patcharp/openobserve:{}",
                metadata.company_release.unwrap().trim_start_matches('v')
            );
            assert_eq!(metadata.docker_image, Some(expected_image.as_str()));
            assert!(metadata.source.is_some());
        }
    }
}
