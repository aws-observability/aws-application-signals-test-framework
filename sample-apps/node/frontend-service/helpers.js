'use strict';

/**
 * Helper functions for the Service Events FunctionCall signal.
 *
 * Service Events function instrumentation (OTEL_AWS_SERVICE_EVENTS_PACKAGES_INCLUDE) is matched
 * (minimatch, matchBase) against the full file path of every require()'d module, so the functions
 * that should emit the `service.function.duration` metric must live in a separate required module
 * — the entry script (index.js) is never transformed. The Service Events EC2 cell sets
 * PACKAGES_INCLUDE to `**\/helpers.js` so the functions below are instrumented.
 *
 * The functions call each other so the captured call_path has more than one frame:
 *   processData -> validateInput, computeResult, formatResponse.
 */

/**
 * Error class mirroring Python's ValueError so the exception-triggered IncidentSnapshot and the
 * EndpointErrorMetric `count` data point carry a meaningful `exception_type` across SDKs.
 */
class ValueError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValueError';
  }
}

// Throws ValueError on a falsy value; this is the function the /exception route trips so the
// exception incident records exception_type=ValueError, function_name=helpers.validateInput.
function validateInput(value) {
  if (!value) {
    throw new ValueError('Invalid input');
  }
  return true;
}

function computeResult(x) {
  return x * 2;
}

function formatResponse(data) {
  return {
    formatted: true,
    payload: data,
  };
}

// Happy-path entry point exercised by /success: drives the success-status FunctionCall data point
// for service.function.duration (status=success) by calling the other instrumented helpers.
function processData(input) {
  validateInput(input);
  const result = computeResult((input && input.length) || 0);
  return formatResponse({ processed: true, result });
}

module.exports = {
  ValueError,
  validateInput,
  computeResult,
  formatResponse,
  processData,
};
