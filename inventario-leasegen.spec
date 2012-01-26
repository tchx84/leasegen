Name:		inventario-leasegen
Version:	0.9
Release:	1%{?dist}
Summary:	inventario lease generator

Group:		Applications/Internet
License:	GPL
URL:		http://laptop.org
Source0:	%{name}-%{version}.tar.gz
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

Requires:	rubygem-activeresource rubygem-parseconfig
Requires(pre): shadow-utils

BuildArch: noarch

%description
inventario lease generator

%prep
%setup -q


%build
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/var/%{name}/{etc,lib,var}
cp -a run.rb $RPM_BUILD_ROOT/var/%{name}
cp -a etc/leasegen.conf.example $RPM_BUILD_ROOT/var/%{name}/etc
cp -a lib/*.rb $RPM_BUILD_ROOT/var/%{name}/lib

mkdir -p $RPM_BUILD_ROOT/usr/bin
ln -s /var/%{name}/run.rb $RPM_BUILD_ROOT/usr/bin/%{name}

mkdir -p $RPM_BUILD_ROOT/var/lib/xo-activations


%clean
rm -rf $RPM_BUILD_ROOT

%pre
getent group inventario >/dev/null || groupadd -r inventario


%files
%defattr(-,root,root,-)
%doc USAGE README
%dir /var/%{name}
/var/%{name}/etc
/var/%{name}/lib
/var/%{name}/*.rb
%attr(0775, -, inventario) /var/%{name}/var
%attr(0755, -, inventario) /var/lib/xo-activations
/usr/bin/%{name}


%changelog
