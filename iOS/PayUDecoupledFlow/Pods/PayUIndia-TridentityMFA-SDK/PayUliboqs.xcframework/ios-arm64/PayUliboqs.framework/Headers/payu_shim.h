#ifndef PAYU_SHIM_H
#define PAYU_SHIM_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* Public aliases exposed for Swift/C users who require PayU_* names. */
typedef enum {
    PayU_OQS_SUCCESS = 0,
    PayU_OQS_ERROR = 1
} PayU_OQS_STATUS;

typedef struct PayU_OQS_SIG PayU_OQS_SIG;

#define PayU_OQS_SIG_ALG_ML_DSA_65 "ML-DSA-65"

PayU_OQS_SIG *PayU_OQS_SIG_new(const char *method_name);
PayU_OQS_STATUS PayU_OQS_SIG_keypair(const PayU_OQS_SIG *sig, uint8_t *public_key, uint8_t *secret_key);
PayU_OQS_STATUS PayU_OQS_SIG_sign(const PayU_OQS_SIG *sig, uint8_t *signature, size_t *signature_len, const uint8_t *message, size_t message_len, const uint8_t *secret_key);
void PayU_OQS_SIG_free(PayU_OQS_SIG *sig);

#endif /* PAYU_SHIM_H */
