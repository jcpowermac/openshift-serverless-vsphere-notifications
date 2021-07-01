FROM quay.io/jcallen/powercli:latest

ADD notification.ps1 /
RUN export POWERSHELL_TELEMETRY_OPTOUT=1 && \
	pwsh -NoLogo -NoProfile -Command " \
          \$ErrorActionPreference = 'Stop' ; \
          \$ProgressPreference = 'SilentlyContinue' ; \
          Set-PSRepository -Name PSGallery -InstallationPolicy Trusted ; \
          Install-Module -Force -Scope AllUsers PSSlack"

ENTRYPOINT ["/bin/pwsh"]

#CMD [""]

#FROM mcr.microsoft.com/powershell:centos-8
#
#RUN dnf upgrade --refresh -y
#
#RUN export POWERSHELL_TELEMETRY_OPTOUT=1 && \
#	pwsh -NoLogo -NoProfile -Command " \
#          \$ErrorActionPreference = 'Stop' ; \
#          \$ProgressPreference = 'SilentlyContinue' ; \
#          Set-PSRepository -Name PSGallery -InstallationPolicy Trusted ; \
#          Install-Module -Scope AllUsers VMware.PowerCLI"
