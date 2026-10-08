# Isolated rc3 validation

This branch stages a hash-verified patch over main commit d718a6b. The workflow applies the candidate in its temporary checkout before running portable tests, native Foundation tests, and an iOS arm64 build. It has read-only repository permissions and never changes main. Only the uploaded artifact is the patched candidate; the unpatched source files in this staging branch are not a rc3 checkout. SOURCE_HASHES.json identifies the exact tested files. The source ZIP delivered separately contains normal, expanded source files rather than this staging mechanism.
