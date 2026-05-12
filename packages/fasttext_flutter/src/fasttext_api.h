// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.
// C ABI wrapper for the fastText C++ library.
// This header is the single source of truth consumed by ffigen.

#pragma once

#if _WIN32
#define FT_EXPORT __declspec(dllexport)
#else
#define FT_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>

/// Opaque handle to a loaded fastText model instance.
typedef void* FastTextHandle;

/// Creates a new (empty) FastText model handle.
/// Returns NULL on allocation failure.
FT_EXPORT FastTextHandle ft_create(void);

/// Destroys a model handle and frees all associated memory.
/// Safe to call with NULL.
FT_EXPORT void ft_destroy(FastTextHandle handle);

/// Loads a fastText model from |path| (supports .bin and .ftz).
/// Returns 0 on success, -1 on failure.
/// On failure, up to |err_len-1| bytes of the error message are written to
/// |err| (NUL-terminated).
FT_EXPORT int ft_load_model(FastTextHandle handle,
                  const char* path,
                  char* err,
                  int err_len);

/// Runs supervised prediction on |text|, returning the top-|k| labels/probs.
///
/// [out] labels    – caller-allocated array of char* pointers (size >= k).
///                   Each element is malloc'd by this function; caller must
///                   call ft_free_labels(labels, *count) when done.
/// [out] probs     – caller-allocated float array (size >= k).
/// [out] count     – actual number of predictions returned (may be < k).
///
/// Returns 0 on success, -1 on failure (error written to err/err_len).
FT_EXPORT int ft_predict_k(FastTextHandle handle,
                 const char* text,
                 int k,
                 float threshold,
                 char** labels,
                 float* probs,
                 int* count,
                 char* err,
                 int err_len);

/// Computes the sentence vector for |text| into |out|.
///
/// [out] out – caller-allocated float array; must be at least
///             ft_get_dimension(handle) elements.
/// [out] dim – populated with the dimension of the output vector.
///
/// Returns 0 on success, -1 on failure.
FT_EXPORT int ft_get_sentence_vector(FastTextHandle handle,
                           const char* text,
                           float* out,
                           int* dim,
                           char* err,
                           int err_len);

/// Returns the embedding dimension of the loaded model, or -1 if not loaded.
FT_EXPORT int ft_get_dimension(FastTextHandle handle);

/// Returns the number of output labels in a supervised model.
/// Returns 0 for unsupervised (cbow/skipgram) models.
FT_EXPORT int ft_get_label_count(FastTextHandle handle);

/// Returns the model type:
///   1 = cbow (unsupervised)
///   2 = skipgram (unsupervised)
///   3 = supervised
///  -1 = unknown/not loaded
FT_EXPORT int ft_get_model_type(FastTextHandle handle);

/// Frees an array of |count| label strings previously returned by ft_predict_k.
FT_EXPORT void ft_free_labels(char** labels, int count);

#ifdef __cplusplus
}  // extern "C"
#endif
