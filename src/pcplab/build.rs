// Copyright 2026 PCPLAB
// SPDX-License-Identifier: AGPL-3.0-or-later

mod validation {
    include!("src/build_metadata/validation.rs");
}

use std::{env, fs, path::Path, process::Command};

use validation::{
    ReleaseInputs, parse_root_package_version, parse_upstream_env, validate_release_inputs,
};

const BUILD_ENV_KEYS: &[&str] = &[
    "PCPLAB_RELEASE",
    "PCPLAB_FORK_SHA",
    "PCPLAB_BUILD_TIMESTAMP",
    "PCPLAB_SOURCE_URL",
];

fn main() {
    for key in BUILD_ENV_KEYS {
        println!("cargo:rerun-if-env-changed={key}");
    }

    let manifest_dir = env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is set by Cargo");
    let repo_root = Path::new(&manifest_dir)
        .parent()
        .and_then(Path::parent)
        .expect("src/pcplab must live below the repository root");
    let upstream_path = repo_root.join(".fork/upstream.env");
    let root_manifest_path = repo_root.join("Cargo.toml");

    println!("cargo:rerun-if-changed={}", upstream_path.display());
    println!("cargo:rerun-if-changed={}", root_manifest_path.display());

    let upstream = parse_upstream_env(
        &fs::read_to_string(&upstream_path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", upstream_path.display())),
    )
    .unwrap_or_else(|error| panic!("invalid {}: {error}", upstream_path.display()));
    let root_version =
        parse_root_package_version(&fs::read_to_string(&root_manifest_path).unwrap_or_else(
            |error| panic!("failed to read {}: {error}", root_manifest_path.display()),
        ))
        .unwrap_or_else(|error| panic!("invalid root Cargo.toml: {error}"));

    if root_version != upstream.source_version {
        panic!(
            "root Cargo.toml version {root_version} does not match UPSTREAM_SOURCE_VERSION {}",
            upstream.source_version
        );
    }

    let release = env_value("PCPLAB_RELEASE");
    let fork_sha = env_value("PCPLAB_FORK_SHA");
    let build_timestamp = env_value("PCPLAB_BUILD_TIMESTAMP");
    let source_url = env_value("PCPLAB_SOURCE_URL");

    let (release_channel, company_release, fork_sha, build_timestamp, source_url) = if release
        .is_some()
        || fork_sha.is_some()
        || build_timestamp.is_some()
        || source_url.is_some()
    {
        let inputs = ReleaseInputs {
            release: release.as_deref().unwrap_or_default(),
            fork_sha: fork_sha.as_deref().unwrap_or_default(),
            build_timestamp: build_timestamp.as_deref().unwrap_or_default(),
            source_url: source_url.as_deref().unwrap_or_default(),
        };
        let channel = validate_release_inputs(&inputs, &upstream, &root_version)
            .unwrap_or_else(|error| panic!("invalid claimed PCPLAB release metadata: {error}"));

        if let Some(head) = git_head(repo_root)
            && head != inputs.fork_sha
        {
            panic!(
                "PCPLAB_FORK_SHA {} does not match checked-out HEAD {head}",
                inputs.fork_sha
            );
        }

        (
            channel,
            inputs.release.to_owned(),
            inputs.fork_sha.to_owned(),
            inputs.build_timestamp.to_owned(),
            inputs.source_url.to_owned(),
        )
    } else {
        let detected_sha = git_head(repo_root).unwrap_or_default();
        let detected_source = if detected_sha.is_empty() {
            String::new()
        } else {
            format!("https://github.com/pcplabme/openobserve/tree/{detected_sha}")
        };
        (
            "development",
            String::new(),
            detected_sha,
            String::new(),
            detected_source,
        )
    };

    emit("PCPLAB_BUILD_DISTRIBUTION", "PCPLAB OpenObserve OSS fork");
    emit("PCPLAB_BUILD_RELEASE_CHANNEL", release_channel);
    emit("PCPLAB_BUILD_COMPANY_RELEASE", &company_release);
    emit("PCPLAB_BUILD_FORK_SHA", &fork_sha);
    emit(
        "PCPLAB_BUILD_UPSTREAM_REPOSITORY",
        upstream.repository.trim_end_matches(".git"),
    );
    emit(
        "PCPLAB_BUILD_UPSTREAM_SOURCE_VERSION",
        &upstream.source_version,
    );
    emit("PCPLAB_BUILD_UPSTREAM_BASE_SHA", &upstream.base_sha);
    emit("PCPLAB_BUILD_UPSTREAM_BASE_TYPE", &upstream.base_type);
    emit(
        "PCPLAB_BUILD_UPSTREAM_SECURITY_PATCH_SHAS",
        &upstream.security_patch_shas,
    );
    emit(
        "PCPLAB_BUILD_UPSTREAM_SECURITY_ADVISORIES",
        &upstream.security_advisories,
    );
    emit("PCPLAB_BUILD_TIMESTAMP_VALUE", &build_timestamp);
    let docker_image = if company_release.is_empty() {
        String::new()
    } else {
        format!(
            "patcharp/openobserve:{}",
            company_release.trim_start_matches('v')
        )
    };
    emit("PCPLAB_BUILD_DOCKER_IMAGE", &docker_image);
    emit("PCPLAB_BUILD_LICENSE", "AGPL-3.0");
    emit("PCPLAB_BUILD_SOURCE", &source_url);
}

fn env_value(key: &str) -> Option<String> {
    env::var(key).ok().filter(|value| !value.is_empty())
}

fn git_head(repo_root: &Path) -> Option<String> {
    let output = Command::new("git")
        .args(["rev-parse", "--verify", "HEAD"])
        .current_dir(repo_root)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let sha = String::from_utf8(output.stdout).ok()?.trim().to_owned();
    validation::is_full_sha(&sha).then_some(sha)
}

fn emit(key: &str, value: &str) {
    assert!(
        !value.contains(['\n', '\r']),
        "build metadata {key} contains a newline"
    );
    println!("cargo:rustc-env={key}={value}");
}
