#!/bin/bash

set -e

#
# Sets envioment for multi-platform builds.
#
# $1 - The buildkit server.
# $2 - The target platforms.
#
# Examples:
#
#   setup "tcp://0.0.0.0:1234" "linux/and64,linux/arm64"
#
setup() {
  declare -r buildkit_host=="${1}"
  declare -r platforms=($(echo "${2}" | tr ',' '\n'))

  # Enabling server experimental features
  echo '{"experimental":true}' | sudo tee /etc/docker/daemon.json
  sudo service docker restart

  # Registering file format recognizers
  sudo docker run --privileged linuxkit/binfmt:v0.6

  local worker_platforms
  for platform in "${platforms[@]}"; do
    worker_platforms="${worker_platforms} --oci-worker-platform ${platform}"
  done

  if [[ "${buildkit_host}" =~ ^tcp://.*:([0-9]*) ]]; then
    local port="${BASH_REMATCH[1]}"
  else
    printf "Port is not specified in \n" "${buildkit_host}"
    exit 1
  fi

  # Starting BuildKit in a container
  sudo docker run -d --privileged \
    -p "${port}":"${port}" \
    --name buildkit moby/buildkit:latest \
    --addr "${buildkit_host}" \
    ${worker_platforms}

  # Extracting buildctl into /usr/bin/
  sudo docker cp buildkit:/usr/bin/buildctl /usr/bin/
}

#
# Builds platform-specific Docker images.
#
# $1 - The image name.
# $2 - The image tag.
# $3 - The target platforms.
#
# Examples:
#
#   build "foo/bar" "1.0.0" linux/amd64,linux/arm64"
#
build() {
  declare -r image="${1}"
  declare -r tag="${2}"
  declare -r platforms=($(echo "${3}" | tr ',' '\n'))

  # A workaround for https://github.com/moby/buildkit/issues/863
  mkfifo fifo.tar
  trap 'rm fifo.tar' EXIT

  for platform in "${platforms[@]}"; do

    # Form a platform tag, e.g. "1.0.0-linux-amd64".
    local platform_tag="${tag}-${platform//\//-}"

    # Build a platform spceific Docker image
    # and load it back to the local Docker.
    buildctl build --frontend dockerfile.v0 \
      --frontend-opt platform="${platform}" \
      --local dockerfile=. \
      --local context=. \
      --exporter docker \
      --exporter-opt name="${image}:${platform_tag}" \
      --exporter-opt output=fifo.tar \
      & docker load < fifo.tar & wait

  done
}

"$@"