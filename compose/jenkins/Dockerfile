# compose/jenkins/Dockerfile
# Jenkins LTS + security tooling ที่ pipeline ต้องใช้ (bake ให้ reproducible):
#   - Trivy CLI            → stage 'Trivy scan'   (trivyScan)
#   - SonarScanner CLI     → stage 'SonarQube'    (sonarScan)
#   - sonar Jenkins plugin → step withSonarQubeEnv / waitForQualityGate (hard gate)
FROM jenkins/jenkins:lts-jdk17

# bump เวอร์ชันได้ที่นี่
ARG TRIVY_VERSION=0.73.0                    # https://github.com/aquasecurity/trivy/releases
ARG SONAR_SCANNER_VERSION=6.2.1.4610        # https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/

USER root

# Trivy CLI
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin "v${TRIVY_VERSION}" \
    && trivy --version

# SonarScanner CLI (ตัว x64 bundle JRE มาในตัว)
RUN curl -sfLo /tmp/sonar-scanner.zip \
      "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
    && unzip -q /tmp/sonar-scanner.zip -d /opt \
    && ln -s "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner" /usr/local/bin/sonar-scanner \
    && rm /tmp/sonar-scanner.zip \
    && sonar-scanner --version

# SonarQube Scanner for Jenkins plugin (ให้มี step withSonarQubeEnv / waitForQualityGate)
RUN jenkins-plugin-cli --plugins sonar

# Node.js 20 (สำหรับ build Vite/React ของ sample-app: npm ci && npm run build)
# copy จาก official image แทน apt/nodesource — ไม่ต้องต่อ deb.debian.org (โดน 403 หลัง proxy)
COPY --from=node:20-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:20-bookworm-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node -v && npm -v

# Docker CLI + compose plugin (static binary) → stage 'Deploy' สั่ง docker compose ผ่าน socket ของ host
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:27-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

USER jenkins
