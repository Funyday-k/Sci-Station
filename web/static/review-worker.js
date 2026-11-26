/* Same-origin worker: expensive exact comparisons never block the editor. */
'use strict';
importScripts('review-metrics.js');
self.onmessage = function (event) {
  const request = event.data || {};
  try {
    self.postMessage({ id: request.id, metrics: self.RoundtableReviewMetrics.analyze(request.diff, request.path) });
  } catch (_) {
    self.postMessage({ id: request.id, metrics: { status: 'unavailable', document: false, lines: null, reason: 'worker-comparison-failed' } });
  }
};
