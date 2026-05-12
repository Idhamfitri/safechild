// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.
// C ABI wrapper implementation for the fastText C++ library.

#include "fasttext_api.h"
#include "third_party/fasttext/fasttext.h"

#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <sstream>
#include <stdexcept>

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

static void copy_error(const char* msg, char* err_buf, int err_len) {
  if (!err_buf || err_len <= 0) return;
  std::strncpy(err_buf, msg, static_cast<size_t>(err_len) - 1);
  err_buf[err_len - 1] = '\0';
}

static void clear_error(char* err_buf, int err_len) {
  if (err_buf && err_len > 0) err_buf[0] = '\0';
}

// ---------------------------------------------------------------------------
// Public C API
// ---------------------------------------------------------------------------

FastTextHandle ft_create(void) {
  try {
    return new fasttext::FastText();
  } catch (...) {
    return nullptr;
  }
}

void ft_destroy(FastTextHandle handle) {
  delete static_cast<fasttext::FastText*>(handle);
}

int ft_load_model(FastTextHandle handle,
                  const char* path,
                  char* err,
                  int err_len) {
  clear_error(err, err_len);
  if (!handle || !path) {
    copy_error("null handle or path", err, err_len);
    return -1;
  }
  try {
    static_cast<fasttext::FastText*>(handle)->loadModel(std::string(path));
    return 0;
  } catch (const std::exception& e) {
    copy_error(e.what(), err, err_len);
    return -1;
  } catch (...) {
    copy_error("unknown error loading model", err, err_len);
    return -1;
  }
}

int ft_predict_k(FastTextHandle handle,
                 const char* text,
                 int k,
                 float threshold,
                 char** labels,
                 float* probs,
                 int* count,
                 char* err,
                 int err_len) {
  clear_error(err, err_len);
  if (!handle || !text || !labels || !probs || !count) {
    copy_error("null argument", err, err_len);
    return -1;
  }
  *count = 0;

  try {
    auto* ft = static_cast<fasttext::FastText*>(handle);
    // FastText expects input with a trailing newline in a stream.
    std::istringstream istream(std::string(text) + "\n");

    std::vector<std::pair<fasttext::real, std::string>> predictions;
    ft->predictLine(istream, predictions, static_cast<int32_t>(k),
                    static_cast<fasttext::real>(threshold));

    int n = static_cast<int>(predictions.size());
    for (int i = 0; i < n; ++i) {
      probs[i] = static_cast<float>(predictions[i].first);
      const std::string& label = predictions[i].second;
      char* buf = static_cast<char*>(std::malloc(label.size() + 1));
      if (!buf) {
        // Cleanup already-allocated strings
        for (int j = 0; j < i; ++j) std::free(labels[j]);
        copy_error("out of memory", err, err_len);
        return -1;
      }
      std::memcpy(buf, label.data(), label.size() + 1);
      labels[i] = buf;
    }
    *count = n;
    return 0;
  } catch (const std::exception& e) {
    copy_error(e.what(), err, err_len);
    return -1;
  } catch (...) {
    copy_error("unknown prediction error", err, err_len);
    return -1;
  }
}

int ft_get_sentence_vector(FastTextHandle handle,
                           const char* text,
                           float* out,
                           int* dim,
                           char* err,
                           int err_len) {
  clear_error(err, err_len);
  if (!handle || !text || !out || !dim) {
    copy_error("null argument", err, err_len);
    return -1;
  }
  try {
    auto* ft = static_cast<fasttext::FastText*>(handle);
    int d = ft->getDimension();
    fasttext::Vector vec(d);
    std::istringstream istream(std::string(text) + "\n");
    ft->getSentenceVector(istream, vec);
    *dim = d;
    for (int i = 0; i < d; ++i) {
      out[i] = static_cast<float>(vec[i]);
    }
    return 0;
  } catch (const std::exception& e) {
    copy_error(e.what(), err, err_len);
    return -1;
  } catch (...) {
    copy_error("unknown sentence-vector error", err, err_len);
    return -1;
  }
}

int ft_get_dimension(FastTextHandle handle) {
  if (!handle) return -1;
  try {
    return static_cast<int>(
        static_cast<fasttext::FastText*>(handle)->getDimension());
  } catch (...) {
    return -1;
  }
}

int ft_get_label_count(FastTextHandle handle) {
  if (!handle) return -1;
  try {
    auto* ft = static_cast<fasttext::FastText*>(handle);
    // Unsupervised models (cbow/sg) have 0 labels — return 0 gracefully.
    return static_cast<int>(ft->getDictionary()->nlabels());
  } catch (...) {
    return 0;
  }
}

int ft_get_model_type(FastTextHandle handle) {
  if (!handle) return -1;
  try {
    auto* ft = static_cast<fasttext::FastText*>(handle);
    // model_name enum: cbow=1, sg=2, sup=3
    return static_cast<int>(ft->getArgs().model);
  } catch (...) {
    return -1;
  }
}

void ft_free_labels(char** labels, int count) {
  if (!labels) return;
  for (int i = 0; i < count; ++i) {
    std::free(labels[i]);
  }
}
