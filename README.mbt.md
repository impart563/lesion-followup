# lesion-followup

An offline MoonBit library for reviewing a fixed set of manually measured CT
target lesions. It keeps baseline and historical-minimum references explicit
and returns each target-only category together with its measurement evidence.

The library implements a documented subset of RECIST 1.1. It does not assess
overall response, read images, select targets, or recommend treatment. Examples
are synthetic. The caller supplies the target set and confirms image comparability.

The public facade exports domain types, validation, ordered replay, and exact
study-JSON / follow-up-CSV parsing. Diameters use tenths of a millimetre and
thresholds are compared as integers.
