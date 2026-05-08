# Contributing

Two checks worth running locally before opening a PR.

The fast one catches accidental use of Perl syntax newer than the floor declared in the four `Makefile.PL` files:

```sh
cpanm Test::MinimumVersion         # one-time
cd server && prove -v xt/minimum_version.t
```

It scans `server/`, `server/api/`, and `client/` from a single test file. The floor literal lives in `xt/minimum_version.t` next to a list of the four `Makefile.PL` sites; if you bump `MIN_PERL_VERSION`, move all of them together.

The thorough one runs the full unit-test pass against the actual floor Perl, in the same Docker image our matrix CI uses. This also catches CPAN dependencies whose declared minimum Perl exceeds ours — `cpanm` refuses to install them and the build fails loudly:

```sh
docker run --rm -v "$PWD:/work" -w /work perldocker/perl-tester:5.22 bash -c '
  cpanm -n Test::MinimumVersion &&
  cd server && perl Makefile.PL && cpanm -n --installdeps . && make test &&
  cd ../client && perl Makefile.PL && cpanm -n --installdeps . && make test
'
```

Replace `5.22` with whatever `MIN_PERL_VERSION` says today. The matrix CI in `.github/workflows/ci-perl-floor.yml` runs this shape on every PR across the floor, a couple of intermediates, and `latest`, so anything you miss locally fails there instead.
