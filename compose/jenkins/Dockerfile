# compose/jenkins/Dockerfile
# Jenkins LTS + Trivy CLI (สำหรับ security gate — stage 'Security scan')
# base image มีแค่ docker.sock mount แต่ไม่มี trivy → bake ใส่ตรงนี้ให้ reproducible
FROM jenkins/jenkins:lts-jdk17

# bump เวอร์ชันได้ที่นี่ (ดู https://github.com/aquasecurity/trivy/releases)
ARG TRIVY_VERSION=0.73.0

USER root
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin "v${TRIVY_VERSION}" \
    && trivy --version
USER jenkins
