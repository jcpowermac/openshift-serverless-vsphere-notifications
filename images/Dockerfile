FROM mcr.microsoft.com/powershell:ubi-9

RUN dnf upgrade --refresh -y && \
    dnf install bind-utils -y

ENV HOME=/home/user

RUN mkdir /projects ${HOME} && \
    for f in "${HOME}" "/etc/passwd" "/projects"; do \
      echo "Changing permissions on ${f}" && chgrp -R 0 ${f} && \
      chmod -R g+rwX ${f}; \
    done

ADD scripts/* /projects/
ADD entrypoint.sh /

RUN curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | tar -C /bin -xvzf - govc

RUN export POWERSHELL_TELEMETRY_OPTOUT=1 && \
	pwsh -NoLogo -NoProfile -Command " \
          \$ErrorActionPreference = 'Stop' ; \
          \$ProgressPreference = 'SilentlyContinue' ; \
          Set-PSRepository -Name PSGallery -InstallationPolicy Trusted ; \
          Install-Module -Force -Scope AllUsers PSSlack ; \
          Install-Module -Scope AllUsers VMware.PowerCLI ; \
          Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCeip:\$false -Confirm:\$false"

RUN for f in "${HOME}" "/etc/hosts"; do \
      echo "Changing permissions on ${f}" && chgrp -R 0 ${f} && \
      chmod -R g+rwX ${f}; \
    done

WORKDIR /projects
ENTRYPOINT ["/entrypoint.sh"]
