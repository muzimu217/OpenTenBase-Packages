Name:           opentenbase
Version:        5.0.0
Release:        1
Summary:        OpenTenBase distributed database system
License:        BSD
URL:            https://github.com/OpenTenBase/OpenTenBase
BuildArch:      aarch64
Source0:        opentenbase-5.0-aarch64.tar.gz

%description
OpenTenBase is an advanced enterprise-level database management system
based on PostgreSQL. It supports distributed transactions, parallel
computing, security, management, and audit functions.

%prep
%setup -q -c -n opentenbase

%install
mkdir -p %{buildroot}/usr/lib/opentenbase
cp -a bin %{buildroot}/usr/lib/opentenbase/
cp -a lib %{buildroot}/usr/lib/opentenbase/
cp -a share %{buildroot}/usr/lib/opentenbase/
cp -a include %{buildroot}/usr/lib/opentenbase/

mkdir -p %{buildroot}/usr/bin
for f in %{buildroot}/usr/lib/opentenbase/bin/*; do
    bname=$(basename "$f")
    ln -s /usr/lib/opentenbase/bin/"$bname" %{buildroot}/usr/bin/"$bname"
done

mkdir -p %{buildroot}/etc/ld.so.conf.d
echo '/usr/lib/opentenbase/lib' > %{buildroot}/etc/ld.so.conf.d/opentenbase.conf

%files
/usr/lib/opentenbase
/usr/bin/*
/etc/ld.so.conf.d/opentenbase.conf

%post
ldconfig

%postun
ldconfig
