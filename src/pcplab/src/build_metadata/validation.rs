// Copyright 2026 PCPLAB
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::BTreeMap;

#[derive(Debug, PartialEq, Eq)]
pub(crate) struct UpstreamMetadata {
    pub repository: String,
    pub source_version: String,
    pub base_sha: String,
    pub base_type: String,
    pub security_patch_shas: String,
    pub security_advisories: String,
}

pub(crate) struct ReleaseInputs<'a> {
    pub release: &'a str,
    pub fork_sha: &'a str,
    pub build_timestamp: &'a str,
    pub source_url: &'a str,
}

pub(crate) fn parse_upstream_env(contents: &str) -> Result<UpstreamMetadata, String> {
    let mut values = BTreeMap::new();
    for (line_number, raw_line) in contents.lines().enumerate() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (key, value) = line
            .split_once('=')
            .ok_or_else(|| format!("line {} is not KEY=VALUE", line_number + 1))?;
        if values.insert(key.to_owned(), value.to_owned()).is_some() {
            return Err(format!("duplicate key {key}"));
        }
    }

    let required = |key: &str| -> Result<String, String> {
        values
            .get(key)
            .filter(|value| !value.is_empty())
            .cloned()
            .ok_or_else(|| format!("missing {key}"))
    };
    let optional = |key: &str| values.get(key).cloned().unwrap_or_default();

    let metadata = UpstreamMetadata {
        repository: required("UPSTREAM_REPOSITORY")?,
        source_version: required("UPSTREAM_SOURCE_VERSION")?,
        base_sha: required("UPSTREAM_BASE_SHA")?,
        base_type: required("UPSTREAM_BASE_TYPE")?,
        security_patch_shas: optional("UPSTREAM_SECURITY_PATCH_SHAS"),
        security_advisories: optional("UPSTREAM_SECURITY_ADVISORIES"),
    };

    if metadata.repository != "https://github.com/openobserve/openobserve.git" {
        return Err("UPSTREAM_REPOSITORY must name the public OpenObserve repository".to_owned());
    }
    if !is_semver_triplet(&metadata.source_version) {
        return Err("UPSTREAM_SOURCE_VERSION must be a numeric semver triplet".to_owned());
    }
    if !is_full_sha(&metadata.base_sha) {
        return Err("UPSTREAM_BASE_SHA must be a lowercase 40-character SHA".to_owned());
    }
    if !matches!(
        metadata.base_type.as_str(),
        "release-tag" | "main-development" | "security-cherry-pick"
    ) {
        return Err(format!(
            "unsupported UPSTREAM_BASE_TYPE: {}",
            metadata.base_type
        ));
    }
    Ok(metadata)
}

pub(crate) fn parse_root_package_version(contents: &str) -> Result<String, String> {
    let mut in_package = false;
    for raw_line in contents.lines() {
        let line = raw_line.trim();
        if line.starts_with('[') {
            in_package = line == "[package]";
            continue;
        }
        if in_package && line.starts_with("version") {
            let (_, value) = line
                .split_once('=')
                .ok_or_else(|| "malformed package version".to_owned())?;
            let version = value.trim().trim_matches('"');
            if is_semver_triplet(version) {
                return Ok(version.to_owned());
            }
            return Err("root package version must be a numeric semver triplet".to_owned());
        }
    }
    Err("root [package] version is missing".to_owned())
}

pub(crate) fn validate_release_inputs<'a>(
    inputs: &ReleaseInputs<'_>,
    upstream: &UpstreamMetadata,
    root_version: &str,
) -> Result<&'a str, String> {
    let (tag_version, channel) = parse_release_tag(inputs.release)?;
    if tag_version != upstream.source_version || tag_version != root_version {
        return Err(
            "release tag, upstream metadata, and root package versions disagree".to_owned(),
        );
    }
    if !is_full_sha(inputs.fork_sha) {
        return Err("PCPLAB_FORK_SHA must be a lowercase 40-character SHA".to_owned());
    }
    if !is_utc_timestamp(inputs.build_timestamp) {
        return Err("PCPLAB_BUILD_TIMESTAMP must be an RFC 3339 UTC timestamp".to_owned());
    }
    let expected_source = format!(
        "https://github.com/pcplabme/openobserve/tree/{}",
        inputs.fork_sha
    );
    if inputs.source_url != expected_source {
        return Err(format!("PCPLAB_SOURCE_URL must be {expected_source}"));
    }
    Ok(channel)
}

fn parse_release_tag(tag: &str) -> Result<(&str, &'static str), String> {
    let body = tag
        .strip_prefix('v')
        .ok_or_else(|| "release tag must start with v".to_owned())?;
    let (version, suffix) = body
        .split_once("-pcplab.")
        .ok_or_else(|| "release tag must contain -pcplab.<revision>".to_owned())?;
    if !is_semver_triplet(version) {
        return Err("release tag version must be a numeric semver triplet".to_owned());
    }
    let parts: Vec<_> = suffix.split('.').collect();
    let positive = |value: &str| {
        value.as_bytes().split_first().is_some_and(|(first, rest)| {
            (b'1'..=b'9').contains(first) && rest.iter().all(u8::is_ascii_digit)
        })
    };
    match parts.as_slice() {
        [revision] if positive(revision) => Ok((version, "release")),
        [revision, "rc", rc_revision] if positive(revision) && positive(rc_revision) => {
            Ok((version, "release-candidate"))
        }
        _ => Err("invalid PCPLAB release tag suffix".to_owned()),
    }
}

pub(crate) fn is_full_sha(value: &str) -> bool {
    value.len() == 40
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn is_semver_triplet(value: &str) -> bool {
    let parts: Vec<_> = value.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_digit()))
}

fn is_utc_timestamp(value: &str) -> bool {
    if !(value.len() == 20
        && value.ends_with('Z')
        && value.as_bytes()[4] == b'-'
        && value.as_bytes()[7] == b'-'
        && value.as_bytes()[10] == b'T'
        && value.as_bytes()[13] == b':'
        && value.as_bytes()[16] == b':'
        && value[..4].bytes().all(|byte| byte.is_ascii_digit())
        && value[5..7].bytes().all(|byte| byte.is_ascii_digit())
        && value[8..10].bytes().all(|byte| byte.is_ascii_digit())
        && value[11..13].bytes().all(|byte| byte.is_ascii_digit())
        && value[14..16].bytes().all(|byte| byte.is_ascii_digit())
        && value[17..19].bytes().all(|byte| byte.is_ascii_digit()))
    {
        return false;
    }

    let number = |range: std::ops::Range<usize>| value[range].parse::<u32>().ok();
    let (Some(year), Some(month), Some(day), Some(hour), Some(minute), Some(second)) = (
        number(0..4),
        number(5..7),
        number(8..10),
        number(11..13),
        number(14..16),
        number(17..19),
    ) else {
        return false;
    };
    let leap_year = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let max_day = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap_year => 29,
        2 => 28,
        _ => return false,
    };
    (1..=max_day).contains(&day) && hour < 24 && minute < 60 && second < 60
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE_SHA: &str = "2c17c07a11387536a77e6fb0762a0d1da97fe4f3";

    fn upstream() -> UpstreamMetadata {
        UpstreamMetadata {
            repository: "https://github.com/openobserve/openobserve.git".to_owned(),
            source_version: "0.93.0".to_owned(),
            base_sha: BASE_SHA.to_owned(),
            base_type: "main-development".to_owned(),
            security_patch_shas: String::new(),
            security_advisories: String::new(),
        }
    }

    #[test]
    fn parses_governance_metadata() {
        let parsed = parse_upstream_env(&format!(
            "UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git\nUPSTREAM_SOURCE_VERSION=0.93.0\nUPSTREAM_BASE_SHA={BASE_SHA}\nUPSTREAM_BASE_TYPE=main-development\nUPSTREAM_SECURITY_PATCH_SHAS=abc\nUPSTREAM_SECURITY_ADVISORIES=CVE-1\n"
        ))
        .unwrap();
        assert_eq!(parsed.source_version, "0.93.0");
        assert_eq!(parsed.security_patch_shas, "abc");
    }

    #[test]
    fn parses_only_the_root_package_version() {
        let manifest =
            "[package]\nversion = \"0.93.0\"\n[workspace.package]\nversion = \"0.1.0\"\n";
        assert_eq!(parse_root_package_version(manifest).unwrap(), "0.93.0");
    }

    #[test]
    fn accepts_stable_and_release_candidate_claims() {
        for (release, expected) in [
            ("v0.93.0-pcplab.1", "release"),
            ("v0.93.0-pcplab.1.rc.2", "release-candidate"),
        ] {
            let sha = "0123456789abcdef0123456789abcdef01234567";
            let source = format!("https://github.com/pcplabme/openobserve/tree/{sha}");
            let input = ReleaseInputs {
                release,
                fork_sha: sha,
                build_timestamp: "2026-09-07T12:00:00Z",
                source_url: &source,
            };
            assert_eq!(
                validate_release_inputs(&input, &upstream(), "0.93.0").unwrap(),
                expected
            );
        }
    }

    #[test]
    fn rejects_partial_or_inconsistent_release_claims() {
        let input = ReleaseInputs {
            release: "v0.93.0-pcplab.1",
            fork_sha: "",
            build_timestamp: "2026-09-07T12:00:00Z",
            source_url: "https://github.com/pcplabme/openobserve/tree/not-a-sha",
        };
        assert!(validate_release_inputs(&input, &upstream(), "0.93.0").is_err());
    }

    #[test]
    fn rejects_noncanonical_release_revisions() {
        for release in [
            "v0.93.0-pcplab.01",
            "v0.93.0-pcplab.+1",
            "v0.93.0-pcplab.1+build",
            "v0.93.0-pcplab.1.rc.01",
        ] {
            assert!(parse_release_tag(release).is_err(), "accepted {release}");
        }
    }

    #[test]
    fn rejects_impossible_utc_timestamps() {
        assert!(!is_utc_timestamp("2026-13-07T12:00:00Z"));
        assert!(!is_utc_timestamp("2026-02-29T12:00:00Z"));
        assert!(!is_utc_timestamp("2026-09-07T24:00:00Z"));
        assert!(is_utc_timestamp("2024-02-29T23:59:59Z"));
    }
}
