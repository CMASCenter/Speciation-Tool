#!/bin/csh -f

tr -cd "[:print:]\n" < $PROFILES_RAW > "${PROFILES_RAW}_clean"
tr -cd "[:print:]\n" < $WEIGHTS_RAW  > "${WEIGHTS_RAW}_clean"
tr -cd "[:print:]\n" < $SPECIES_PROPERTIES_RAW  > "${SPECIES_PROPERTIES_RAW}_clean"

setenv PROFILES               "${PROFILES_RAW}_clean"
setenv WEIGHTS                "${WEIGHTS_RAW}_clean"
setenv SPECIES_PROPERTIES     "${SPECIES_PROPERTIES_RAW}_clean"

