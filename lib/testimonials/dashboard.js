/*
 * testimonials dashboard helpers — CSP-safe replacements for inline
 * handlers, which strict script-src policies (nonce or 'self') block.
 *
 * forms with data-confirm ask before submitting; controls with
 * data-autosubmit submit their form on change. Document-level listeners,
 * registered once, so Turbo navigations into the dashboard are fine.
 */
(function () {
  "use strict";

  if (window.__testimonialsDashboardLoaded) return;
  window.__testimonialsDashboardLoaded = true;

  document.addEventListener("submit", function (event) {
    var form = event.target;
    var message = form && form.dataset ? form.dataset.confirm : null;
    if (message && !window.confirm(message)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);

  document.addEventListener("change", function (event) {
    var control = event.target;
    if (!control || !control.dataset || !control.dataset.autosubmit || !control.form) return;
    if (control.form.requestSubmit) {
      control.form.requestSubmit();
    } else {
      control.form.submit();
    }
  });
})();
