/*
 * testimonials widget — self-contained, no framework, no build step.
 *
 * Reads its config from the <script type="application/json"
 * data-testimonials-config> the server renders — re-read on every render so
 * a Turbo visit always reflects the current page's config.
 *
 * Nothing is visible until the widget opens: from the server (an eligible
 * `testimonial_prompt!` arrives as config.autoOpen), from any element carrying
 * `data-testimonial-prompt` (or `data-testimonial-prompt="nps"`), or from
 * window.Testimonials.open() / .openNps().
 *
 * Flow, modeled on iOS's "leave a review": a small star card first; tapping
 * a star expands into the full form (text or recorded video, consent, guest
 * contact fields). NPS asks 0–10, and promoters are offered the testimonial
 * form right after. Auto-opens report shown/dismissed to the throttle
 * ledger; explicit opens don't.
 *
 * On the public collection page the same code renders the form inline into
 * <div data-testimonials-inline> (config.mode === "page").
 */
(function () {
  "use strict";

  var config = readConfig();
  if (!config || window.__testimonialsLoaded) return;
  window.__testimonialsLoaded = true;

  var Z = 2147482000;
  var overlay = null;
  var lastFocused = null;
  var state = null; // one open session: { kind, auto, stage, rating, videoBlob, ... }
  var media = { stream: null, recorder: null, chunks: [], timer: null };

  function ready(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn);
    } else {
      fn();
    }
  }

  ready(function () {
    document.addEventListener("keydown", handleKeydown);
    document.addEventListener("click", handleOpenerClick, true);

    render();
    document.addEventListener("turbo:load", render);

    window.Testimonials = {
      open: function () { openReview(false); },
      openNps: function () { openNps(false); }
    };
  });

  function readConfig() {
    var el = document.querySelector("script[data-testimonials-config]");
    if (!el) return null;
    try {
      return JSON.parse(el.textContent);
    } catch (e) {
      return null;
    }
  }

  function render() {
    config = readConfig() || config;
    injectStyles();

    if (config.mode === "page") {
      renderInline();
      return;
    }

    // Each server-granted auto-open fires exactly once, even if Turbo
    // re-runs render() for the same document.
    var el = document.querySelector("script[data-testimonials-config]");
    if (config.autoOpen && el && !el.dataset.testimonialsHandled) {
      el.dataset.testimonialsHandled = "1";
      setTimeout(function () {
        if (config.autoOpen === "nps") openNps(true);
        else openReview(true);
      }, 600);
    }
  }

  function handleOpenerClick(event) {
    var opener = event.target && event.target.closest
      ? event.target.closest("[data-testimonial-prompt]")
      : null;
    if (!opener) return;
    event.preventDefault();
    event.stopPropagation();
    if (opener.getAttribute("data-testimonial-prompt") === "nps") openNps(false);
    else openReview(false);
  }

  function handleKeydown(event) {
    if (event.key === "Escape" && overlay) close();
  }

  // The backdrop only dismisses while nothing can be lost: the initial star
  // or NPS card, and the thanks screen. Once a form is on screen, closing
  // takes the × button (or Esc) — a stray click must not eat someone's
  // half-written testimonial.
  function dismissible() {
    return !state || state.submitted ||
      state.stage === "rate" || state.stage === "nps" || state.stage === "thanks";
  }

  // --- open / close -----------------------------------------------------------

  function openReview(auto) {
    if (!openSession("testimonial", auto)) return;
    if (config.existing) {
      // One review per user: editing replaces it, so skip the star card and
      // open the form pre-filled.
      prefillExisting();
      showStage(formStage(config.labels.updateTitle));
    } else {
      showStage(rateStage());
    }
  }

  function openNps(auto) {
    if (!config.nps.enabled) return openReview(auto);
    if (!openSession("nps", auto)) return;
    showStage(npsStage());
  }

  function openSession(kind, auto) {
    if (overlay) return false;
    state = { kind: kind, auto: !!auto, rating: 0, submitted: false, videoBlob: null, source: "widget" };
    lastFocused = document.activeElement;

    overlay = document.createElement("div");
    overlay.id = "tml-overlay";
    overlay.addEventListener("mousedown", function (event) {
      if (event.target === overlay && dismissible()) close();
    });

    var dialog = document.createElement("div");
    dialog.id = "tml-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    if (config.rtl) dialog.setAttribute("dir", "rtl");

    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    overlay.addEventListener("keydown", trapFocus);

    if (auto) postEvent(kind, "shown");
    return true;
  }

  function close() {
    if (!overlay) return;
    stopMedia();
    if (state && state.playbackUrl) URL.revokeObjectURL(state.playbackUrl);
    if (state && state.auto && !state.submitted) postEvent(state.kind, "dismissed");
    overlay.remove();
    overlay = null;
    state = null;
    if (lastFocused && lastFocused.focus) lastFocused.focus();
  }

  function dialogEl() {
    return overlay ? overlay.querySelector("#tml-dialog") : document.querySelector("[data-testimonials-inline] .tml-inline");
  }

  function showStage(node) {
    var dialog = dialogEl();
    if (!dialog) return;
    stopMedia();
    dialog.textContent = "";
    dialog.appendChild(node);
    var focusable = dialog.querySelector("textarea, input, button");
    if (focusable && overlay) focusable.focus();
  }

  function trapFocus(event) {
    if (event.key !== "Tab" || !overlay) return;
    var focusable = overlay.querySelectorAll("button, select, textarea, input, a[href], video");
    if (!focusable.length) return;
    var first = focusable[0];
    var last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  // --- inline (public collection page) ----------------------------------------

  function renderInline() {
    var host = document.querySelector("[data-testimonials-inline]");
    if (!host || host.querySelector(".tml-inline")) return;
    var card = document.createElement("div");
    card.className = "tml-inline";
    if (config.rtl) card.setAttribute("dir", "rtl");
    host.appendChild(card);
    state = { kind: "testimonial", auto: false, rating: 0, submitted: false, videoBlob: null, source: "page" };
    if (config.existing) prefillExisting();
    card.appendChild(formStage(config.existing ? config.labels.updateTitle : config.labels.shareTitle));
  }

  // --- stage 1: the iOS-style star card ---------------------------------------

  function rateStage() {
    state.stage = "rate";
    var stage = el("div", "tml-stage");
    stage.appendChild(el("h2", "tml-title", config.labels.enjoying));

    var stars = el("div", "tml-stars tml-stars-big");
    for (var i = 1; i <= 5; i++) {
      stars.appendChild(starButton(i, function (value) {
        state.rating = value;
        showStage(formStage(config.labels.shareTitle));
      }));
    }
    stage.appendChild(stars);
    stage.appendChild(notNowButton());
    return stage;
  }

  function starButton(value, onPick) {
    var button = el("button", "tml-star", "★");
    button.type = "button";
    button.setAttribute("aria-label", config.labels.rateAria.replace("%{count}", value));
    button.addEventListener("mouseenter", function () { paintStars(button.parentNode, value); });
    button.addEventListener("mouseleave", function () { paintStars(button.parentNode, state.rating); });
    button.addEventListener("click", function () {
      paintStars(button.parentNode, value);
      onPick(value);
    });
    return button;
  }

  function paintStars(container, upto) {
    var stars = container.querySelectorAll(".tml-star");
    for (var i = 0; i < stars.length; i++) {
      stars[i].classList.toggle("tml-star-on", i < upto);
    }
  }

  function notNowButton() {
    var button = el("button", "tml-plain", config.labels.notNow);
    button.type = "button";
    button.addEventListener("click", close);
    return button;
  }

  function prefillExisting() {
    state.rating = config.existing.rating || 0;
    state.body = config.existing.body || "";
    state.consent = !!config.existing.consent;
    state.existingVideoUrl = config.existing.videoUrl || null;
  }

  // --- stage 2: the testimonial form ------------------------------------------

  function formStage(title) {
    state.stage = "form";
    state.formTitle = title;
    var stage = el("div", "tml-stage");
    stage.appendChild(header(title));

    var form = document.createElement("form");
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      submitTestimonial(form);
    });

    var stars = el("div", "tml-stars");
    for (var i = 1; i <= 5; i++) {
      stars.appendChild(starButton(i, function (value) { state.rating = value; }));
    }
    paintStars(stars, state.rating);
    form.appendChild(stars);

    var questions = questionsBox();
    if (questions) form.appendChild(questions);

    var textarea = document.createElement("textarea");
    textarea.name = "body";
    textarea.rows = 4;
    textarea.placeholder = config.labels.messagePlaceholder;
    textarea.value = state.body || "";
    form.appendChild(field(config.labels.message, textarea));

    if (config.video.enabled) form.appendChild(videoControl(form));
    if (!config.authenticated) {
      appendGuestFields(form);
      restoreDraftFields(form);
    }
    form.appendChild(consentField());

    var error = el("p", "tml-error");
    error.hidden = true;
    form.appendChild(error);

    var actions = el("div", "tml-actions");
    actions.appendChild(secondaryButton(config.labels.cancel, close));
    var submit = el("button", "tml-primary", config.labels.submit);
    submit.type = "submit";
    actions.appendChild(submit);
    form.appendChild(actions);

    stage.appendChild(form);
    return stage;
  }

  function appendGuestFields(form) {
    var name = document.createElement("input");
    name.type = "text";
    name.name = "name";
    name.autocomplete = "name";
    form.appendChild(field(config.labels.name, name));

    var email = document.createElement("input");
    email.type = "email";
    email.name = "email";
    email.autocomplete = "email";
    form.appendChild(field(config.labels.email, email));

    var title = document.createElement("input");
    title.type = "text";
    title.name = "title_company";
    title.autocomplete = "organization-title";
    form.appendChild(field(config.labels.titleCompany + " (" + config.labels.optional + ")", title));

    if (config.mode === "page" && config.avatars.enabled) {
      var avatar = document.createElement("input");
      avatar.type = "file";
      avatar.name = "avatar";
      avatar.accept = "image/*";
      form.appendChild(field(config.labels.photo + " (" + config.labels.optional + ")", avatar));
    }
  }

  function questionsBox() {
    if (!config.questions.length) return null;
    var box = el("div", "tml-questions");
    box.appendChild(el("strong", null, config.labels.questionsTitle));
    var list = document.createElement("ul");
    config.questions.forEach(function (question) {
      list.appendChild(el("li", null, question));
    });
    box.appendChild(list);
    return box;
  }

  function consentField() {
    var wrap = el("label", "tml-consent");
    var checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.name = "consent";
    // Pre-checked when editing a review that already granted consent, and
    // kept across stage round trips — an update must never silently revoke
    // (or invent) publication consent.
    checkbox.checked = !!state.consent;
    checkbox.addEventListener("change", function () { state.consent = checkbox.checked; });
    wrap.appendChild(checkbox);
    wrap.appendChild(el("span", null, config.consent));
    return wrap;
  }

  // --- video ------------------------------------------------------------------

  function videoControl(form) {
    var wrap = el("div", "tml-field");

    if (state.videoBlob) {
      wrap.appendChild(attachedVideoChip(form, wrap, null, function () {
        state.videoBlob = null;
      }));
      return wrap;
    }

    // Editing a review that already has a video: show it, playable, with a
    // remove control. Removing reveals the record panel again.
    if (state.existingVideoUrl && !state.removeExistingVideo) {
      var playback = document.createElement("video");
      playback.className = "tml-video";
      playback.controls = true;
      playback.playsInline = true;
      playback.preload = "metadata";
      playback.src = state.existingVideoUrl;
      wrap.appendChild(playback);
      wrap.appendChild(attachedVideoChip(form, wrap, playback, function () {
        state.removeExistingVideo = true;
      }));
      return wrap;
    }

    // The strongest testimonials are videos — this is a big, inviting
    // panel-button rather than a modest secondary action.
    var button = el("button", "tml-record");
    button.type = "button";
    button.appendChild(el("span", "tml-record-label", "🎥 " + config.labels.recordVideo));
    button.appendChild(el("span", "tml-record-hint", config.labels.recordVideoHint));
    button.addEventListener("click", function () {
      // The form is about to be replaced by the recorder — keep what the
      // user already typed so it survives the round trip.
      saveDraft(form);
      if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder) {
        showStage(videoStage());
      } else {
        pickVideoFile();
      }
    });
    wrap.appendChild(button);
    return wrap;
  }

  function attachedVideoChip(form, wrap, playback, onRemove) {
    var chip = el("div", "tml-chip");
    chip.appendChild(el("span", "tml-chip-label", "🎥 " + config.labels.videoAttached));
    var remove = el("button", "tml-chip-remove", config.labels.remove);
    remove.type = "button";
    remove.addEventListener("click", function () {
      onRemove();
      if (playback) playback.remove();
      wrap.replaceWith(videoControl(form));
    });
    chip.appendChild(remove);
    return chip;
  }

  // Recording lives in its own stage: camera check -> 3-2-1 -> recording ->
  // review. The guiding questions stay pinned above the preview the whole
  // time, so nobody freezes on camera wondering what to say.
  function videoStage() {
    state.stage = "video";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.videoCheckTitle));

    var questions = questionsBox();
    if (questions) stage.appendChild(questions);

    var frame = el("div", "tml-preview");
    var preview = document.createElement("video");
    preview.className = "tml-video";
    preview.autoplay = true;
    preview.muted = true;
    preview.playsInline = true;
    frame.appendChild(preview);

    var timer = el("div", "tml-timer");
    timer.hidden = true;
    frame.appendChild(timer);

    var countdown = el("div", "tml-countdown");
    countdown.hidden = true;
    frame.appendChild(countdown);
    stage.appendChild(frame);

    var hint = el("p", "tml-hint", config.labels.videoHint);
    stage.appendChild(hint);

    var error = el("p", "tml-error");
    error.hidden = true;
    stage.appendChild(error);

    var actions = el("div", "tml-actions");
    var start = el("button", "tml-primary", config.labels.startRecording);
    start.type = "button";
    var stop = el("button", "tml-primary", config.labels.stopRecording);
    stop.type = "button";
    stop.hidden = true;
    var back = secondaryButton(config.labels.cancel, function () {
      showStage(formStage(state.formTitle || config.labels.shareTitle));
    });
    actions.appendChild(back);
    actions.appendChild(start);
    actions.appendChild(stop);
    stage.appendChild(actions);

    var upload = el("button", "tml-plain", config.labels.uploadInstead);
    upload.type = "button";
    upload.addEventListener("click", function () {
      stopMedia();
      pickVideoFile();
    });
    stage.appendChild(upload);

    navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      .then(function (stream) {
        media.stream = stream;
        preview.srcObject = stream;
      })
      .catch(function () {
        error.textContent = config.labels.errorCamera;
        error.hidden = false;
        start.disabled = true;
      });

    start.addEventListener("click", function () {
      if (!media.stream) return;
      start.disabled = true;
      runCountdown(countdown, 3, function () {
        start.hidden = true;
        stop.hidden = false;
        beginRecording(timer, stop);
      });
    });

    stop.addEventListener("click", function () {
      if (media.recorder && media.recorder.state !== "inactive") media.recorder.stop();
      clearInterval(media.timer);
    });

    return stage;
  }

  function runCountdown(node, from, onDone) {
    var left = from;
    node.hidden = false;
    node.textContent = String(left);
    media.timer = setInterval(function () {
      left -= 1;
      if (left <= 0) {
        clearInterval(media.timer);
        node.hidden = true;
        onDone();
      } else {
        node.textContent = String(left);
      }
    }, 800);
  }

  function beginRecording(timer, stop) {
    media.chunks = [];
    try {
      media.recorder = new MediaRecorder(media.stream, { mimeType: recordingMimeType() });
    } catch (e) {
      media.recorder = new MediaRecorder(media.stream);
    }
    media.recorder.addEventListener("dataavailable", function (event) {
      if (event.data && event.data.size) media.chunks.push(event.data);
    });
    media.recorder.addEventListener("stop", function () {
      var type = media.recorder.mimeType || "video/webm";
      var blob = new Blob(media.chunks, { type: type.split(";")[0] });
      showStage(reviewStage(blob));
    });
    media.recorder.start();
    startTimer(timer, function () { stop.click(); });
  }

  function recordingMimeType() {
    var candidates = ["video/mp4", "video/webm;codecs=vp9,opus", "video/webm"];
    for (var i = 0; i < candidates.length; i++) {
      if (window.MediaRecorder.isTypeSupported(candidates[i])) return candidates[i];
    }
    return "";
  }

  function startTimer(timer, onLimit) {
    var left = config.video.maxSeconds;
    timer.hidden = false;
    timer.textContent = "● " + formatSeconds(left);
    media.timer = setInterval(function () {
      left -= 1;
      timer.textContent = "● " + formatSeconds(left);
      if (left <= 0) {
        clearInterval(media.timer);
        onLimit();
      }
    }, 1000);
  }

  function formatSeconds(total) {
    var minutes = Math.floor(total / 60);
    var seconds = total % 60;
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
  }

  function reviewStage(blob) {
    state.stage = "review";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.shareTitle));

    var playback = document.createElement("video");
    playback.className = "tml-video";
    playback.controls = true;
    playback.playsInline = true;
    // The playback URL lives on the session, NOT on `media`: showStage()
    // tears media down on every transition, which used to revoke this URL
    // the instant the review screen appeared (Safari: WebKitBlobResource
    // error 1, dead player). Revoked on close or when re-recording.
    if (state.playbackUrl) URL.revokeObjectURL(state.playbackUrl);
    state.playbackUrl = URL.createObjectURL(blob);
    playback.src = state.playbackUrl;
    stage.appendChild(playback);

    var error = el("p", "tml-error");
    error.hidden = true;
    stage.appendChild(error);

    var actions = el("div", "tml-actions");
    actions.appendChild(secondaryButton(config.labels.recordAgain, function () {
      showStage(videoStage());
    }));
    var use = el("button", "tml-primary", config.labels.useVideo);
    use.type = "button";
    use.addEventListener("click", function () {
      if (blob.size > config.video.maxSize) {
        error.textContent = config.labels.errorVideoTooLarge;
        error.hidden = false;
        return;
      }
      state.videoBlob = blob;
      showStage(formStage(state.formTitle || config.labels.shareTitle));
    });
    actions.appendChild(use);
    stage.appendChild(actions);
    return stage;
  }

  function pickVideoFile() {
    var input = document.createElement("input");
    input.type = "file";
    input.accept = "video/*";
    input.addEventListener("change", function () {
      var file = input.files && input.files[0];
      if (!file) return;
      state.videoBlob = file;
      showStage(formStage(state.formTitle || config.labels.shareTitle));
    });
    input.click();
  }

  function stopMedia() {
    if (media.timer) clearInterval(media.timer);
    if (media.recorder && media.recorder.state !== "inactive") {
      try { media.recorder.stop(); } catch (e) { /* already stopped */ }
    }
    if (media.stream) {
      media.stream.getTracks().forEach(function (track) { track.stop(); });
    }
    media = { stream: null, recorder: null, chunks: [], timer: null };
  }

  // --- NPS ----------------------------------------------------------------------

  function npsStage() {
    state.stage = "nps";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.npsQuestion));

    var row = el("div", "tml-nps");
    for (var score = 0; score <= 10; score++) {
      row.appendChild(npsButton(score));
    }
    stage.appendChild(row);

    var legend = el("div", "tml-nps-legend");
    legend.appendChild(el("span", null, config.labels.npsLow));
    legend.appendChild(el("span", null, config.labels.npsHigh));
    stage.appendChild(legend);

    stage.appendChild(notNowButton());
    return stage;
  }

  function npsButton(score) {
    var button = el("button", "tml-nps-score", String(score));
    button.type = "button";
    button.addEventListener("click", function () {
      state.rating = score;
      showStage(npsCommentStage(score));
    });
    return button;
  }

  function npsCommentStage(score) {
    state.stage = "form";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.npsQuestion));

    var picked = el("div", "tml-nps-picked", String(score));
    stage.appendChild(picked);

    var form = document.createElement("form");
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      submitNps(form, score);
    });

    var textarea = document.createElement("textarea");
    textarea.name = "comment";
    textarea.rows = 3;
    form.appendChild(field(config.labels.npsCommentLabel + " (" + config.labels.optional + ")", textarea));

    if (!config.authenticated) {
      var email = document.createElement("input");
      email.type = "email";
      email.name = "email";
      email.autocomplete = "email";
      form.appendChild(field(config.labels.email + " (" + config.labels.optional + ")", email));
    }

    var error = el("p", "tml-error");
    error.hidden = true;
    form.appendChild(error);

    var actions = el("div", "tml-actions");
    actions.appendChild(secondaryButton(config.labels.cancel, close));
    var submit = el("button", "tml-primary", config.labels.submit);
    submit.type = "submit";
    actions.appendChild(submit);
    form.appendChild(actions);

    stage.appendChild(form);
    return stage;
  }

  function submitNps(form, score) {
    var data = new FormData();
    data.append("nps[score]", score);
    data.append("nps[comment]", form.querySelector("textarea[name=comment]").value.trim());
    var email = form.querySelector("input[name=email]");
    if (email && email.value) data.append("nps[email]", email.value.trim());
    data.append("nps[page_url]", window.location.href);

    postForm(config.endpoints.nps, data, form, function (body) {
      state.submitted = true;
      if (body && body.offer_testimonial) {
        // The server said this promoter is still eligible for a testimonial
        // ask; this second prompt is an auto-open, so it reports itself.
        state.kind = "testimonial";
        state.submitted = false;
        state.auto = true;
        state.rating = 0;
        state.source = "nps";
        postEvent("testimonial", "shown");
        showStage(formStage(config.labels.promoterTitle));
      } else {
        thanks();
      }
    });
  }

  // --- submit -------------------------------------------------------------------

  function submitTestimonial(form) {
    var body = form.querySelector("textarea[name=body]").value.trim();
    var keepsExistingVideo = state.existingVideoUrl && !state.removeExistingVideo && !state.videoBlob;
    if (!body && !state.videoBlob && !keepsExistingVideo) {
      return showError(form, config.labels.errorBlank);
    }

    if (!config.authenticated) {
      var name = form.querySelector("input[name=name]");
      var email = form.querySelector("input[name=email]");
      if (!name.value.trim() || !email.value.trim()) {
        return showError(form, config.labels.errorContact);
      }
    }

    var data = new FormData();
    data.append("testimonial[body]", body);
    if (state.rating) data.append("testimonial[rating]", state.rating);
    data.append("testimonial[consent_given]", form.querySelector("input[name=consent]").checked ? "1" : "0");
    data.append("testimonial[page_url]", window.location.href);
    data.append("testimonial[source]", state.source);
    ["name", "email", "title_company"].forEach(function (key) {
      var input = form.querySelector('input[name="' + key + '"]');
      if (input && input.value.trim()) data.append("testimonial[" + key + "]", input.value.trim());
    });
    var avatar = form.querySelector("input[name=avatar]");
    if (avatar && avatar.files && avatar.files[0]) {
      data.append("testimonial[avatar]", avatar.files[0]);
    }
    if (state.videoBlob) {
      var extension = (state.videoBlob.type || "video/webm").indexOf("mp4") > -1 ? "mp4" : "webm";
      data.append("testimonial[video_file]", state.videoBlob, "testimonial." + extension);
    } else if (state.removeExistingVideo) {
      data.append("testimonial[remove_video]", "1");
    }

    postForm(config.endpoints.testimonials, data, form, function () {
      state.submitted = true;
      thanks();
    });
  }

  function postForm(endpoint, data, form, onSuccess) {
    var submit = form.querySelector(".tml-primary");
    if (submit) submit.disabled = true;

    fetch(endpoint, {
      method: "POST",
      headers: csrfHeaders(),
      body: data,
      credentials: "same-origin"
    })
      .then(function (response) {
        if (response.ok) {
          return response.json().catch(function () { return {}; }).then(onSuccess);
        }
        return response
          .json()
          .catch(function () { return {}; })
          .then(function (body) {
            var messages = body && body.errors;
            showError(form, (messages && messages[0]) || config.labels.errorSave);
          });
      })
      .catch(function () {
        showError(form, config.labels.errorSave);
      })
      .finally(function () {
        if (submit) submit.disabled = false;
      });
  }

  function postEvent(kind, action) {
    var data = new FormData();
    data.append("kind", kind);
    data.append("event_action", action);
    fetch(config.endpoints.events, {
      method: "POST",
      headers: csrfHeaders(),
      body: data,
      credentials: "same-origin",
      keepalive: true
    }).catch(function () { /* the ledger is best-effort */ });
  }

  function thanks() {
    if (state) state.stage = "thanks";
    var dialog = dialogEl();
    if (!dialog) return;
    dialog.textContent = "";
    var note = el("div", "tml-thanks");
    note.appendChild(el("div", "tml-thanks-mark", "✓"));
    note.appendChild(el("p", null, config.labels.thanks));
    dialog.appendChild(note);
    if (overlay) setTimeout(close, 2200);
  }

  // --- drafts ---------------------------------------------------------------------

  function saveDraft(form) {
    var textarea = form.querySelector("textarea[name=body]");
    if (textarea) state.body = textarea.value;
    var consent = form.querySelector("input[name=consent]");
    if (consent) state.consent = consent.checked;
    state.fields = {};
    ["name", "email", "title_company"].forEach(function (key) {
      var input = form.querySelector('input[name="' + key + '"]');
      if (input) state.fields[key] = input.value;
    });
  }

  function restoreDraftFields(form) {
    if (!state.fields) return;
    Object.keys(state.fields).forEach(function (key) {
      var input = form.querySelector('input[name="' + key + '"]');
      if (input) input.value = state.fields[key];
    });
  }

  // --- small helpers ------------------------------------------------------------

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function header(title) {
    var head = el("div", "tml-head");
    head.appendChild(el("h2", "tml-title", title));
    if (overlay) {
      var closeButton = el("button", "tml-x", "×");
      closeButton.type = "button";
      closeButton.setAttribute("aria-label", config.labels.close);
      closeButton.addEventListener("click", close);
      head.appendChild(closeButton);
    }
    return head;
  }

  function field(labelText, control) {
    var wrap = el("label", "tml-field");
    wrap.appendChild(el("span", null, labelText));
    wrap.appendChild(control);
    return wrap;
  }

  function secondaryButton(text, onClick) {
    var button = el("button", "tml-secondary", text);
    button.type = "button";
    button.addEventListener("click", onClick);
    return button;
  }

  function csrfHeaders() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? { "X-CSRF-Token": meta.content } : {};
  }

  function showError(form, text) {
    var error = form.querySelector(".tml-error");
    if (!error) return;
    error.textContent = text;
    error.hidden = false;
  }

  // --- styles -------------------------------------------------------------------

  function injectStyles() {
    if (document.getElementById("tml-styles")) return;
    var css = [
      "#tml-overlay{position:fixed;inset:0;z-index:" + Z + ";background:rgba(0,0,0,.45);",
      "display:flex;align-items:center;justify-content:center;padding:16px}",
      "#tml-dialog,.tml-inline{width:100%;max-width:440px;max-height:92vh;overflow:auto;",
      "background:#fff;color:#1c2024;border-radius:14px;padding:20px;",
      "font:14px/1.5 system-ui,-apple-system,sans-serif;box-shadow:0 20px 60px rgba(0,0,0,.35)}",
      ".tml-inline{box-shadow:none;border:1px solid #e5e7eb;max-width:520px;margin:0 auto}",
      ".tml-head{display:flex;align-items:flex-start;justify-content:space-between;gap:8px;margin:0 0 12px}",
      ".tml-title{margin:0;font-size:17px}",
      ".tml-x{border:0;background:none;font-size:22px;line-height:1;cursor:pointer;color:inherit;padding:2px 6px}",
      ".tml-stage>.tml-title{display:block;text-align:center;margin-bottom:12px}",
      ".tml-stars{display:flex;justify-content:center;gap:4px;margin:4px 0 12px}",
      ".tml-star{border:0;background:none;cursor:pointer;font-size:26px;line-height:1;padding:2px;color:#d1d5db}",
      ".tml-stars-big .tml-star{font-size:38px}",
      ".tml-star-on{color:#f59e0b}",
      ".tml-plain{display:block;margin:4px auto 0;border:0;background:none;cursor:pointer;",
      "color:#2563eb;font:inherit;padding:6px}",
      ".tml-questions{margin:0 0 12px;padding:10px 12px;border-radius:10px;background:rgba(37,99,235,.07);font-size:13px}",
      ".tml-questions strong{display:block;margin-bottom:4px;font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:#2563eb}",
      ".tml-questions ul{margin:0;padding-inline-start:18px}",
      ".tml-field{display:block;margin-bottom:12px}",
      ".tml-field>span{display:block;margin-bottom:4px;font-weight:600}",
      "#tml-dialog textarea,#tml-dialog input[type=text],#tml-dialog input[type=email],#tml-dialog input[type=file],",
      ".tml-inline textarea,.tml-inline input[type=text],.tml-inline input[type=email],.tml-inline input[type=file]",
      "{width:100%;box-sizing:border-box;padding:8px;border:1px solid #d1d5db;border-radius:8px;",
      "background:inherit;color:inherit;font:inherit}",
      ".tml-stage textarea{resize:vertical}",
      ".tml-consent{display:flex;gap:8px;align-items:flex-start;margin-bottom:12px;font-size:13px;cursor:pointer}",
      ".tml-consent input{margin-top:3px}",
      ".tml-error{color:#dc2626;margin:0 0 12px}",
      ".tml-hint{color:#6b7280;font-size:13px;margin:8px 0}",
      ".tml-actions{display:flex;justify-content:flex-end;gap:8px;flex-wrap:wrap}",
      ".tml-actions button{padding:8px 14px;border-radius:8px;cursor:pointer;font:inherit}",
      ".tml-actions .tml-plain{margin:0}",
      ".tml-secondary{border:1px solid #d1d5db;background:none;color:inherit;padding:8px 14px;border-radius:8px;cursor:pointer;font:inherit}",
      ".tml-primary{border:0;background:#2563eb;color:#fff;font-weight:600;padding:8px 14px;border-radius:8px;cursor:pointer;font:inherit}",
      ".tml-primary:disabled{opacity:.6;cursor:default}",
      ".tml-record{display:flex;flex-direction:column;align-items:center;gap:2px;width:100%;",
      "padding:12px;border:1.5px dashed #2563eb;border-radius:10px;cursor:pointer;",
      "background:rgba(37,99,235,.06);font:inherit}",
      ".tml-record:hover{background:rgba(37,99,235,.12)}",
      ".tml-record-label{color:#2563eb;font-weight:600}",
      ".tml-record-hint{font-size:12px;color:#6b7280}",
      ".tml-chip{display:flex;align-items:center;justify-content:space-between;gap:8px;",
      "padding:10px 12px;border-radius:10px;background:rgba(37,99,235,.07)}",
      ".tml-chip-label{font-weight:600}",
      ".tml-chip-remove{border:0;background:none;color:#2563eb;cursor:pointer;font:inherit;padding:2px 6px}",
      ".tml-video{display:block;width:100%;border-radius:10px;background:#000;aspect-ratio:4/3;margin:0 0 12px}",
      ".tml-preview{position:relative;margin-bottom:4px}",
      ".tml-preview .tml-video{margin-bottom:0}",
      ".tml-timer{position:absolute;top:8px;inset-inline-end:8px;background:rgba(0,0,0,.55);color:#fff;",
      "padding:2px 10px;border-radius:999px;font-weight:600;font-size:13px}",
      ".tml-countdown{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;",
      "font-size:72px;font-weight:700;color:#fff;text-shadow:0 2px 16px rgba(0,0,0,.6)}",
      ".tml-nps{display:flex;gap:4px;justify-content:center;flex-wrap:wrap;margin:4px 0 6px}",
      ".tml-nps-score{min-width:32px;padding:8px 0;border:1px solid #d1d5db;border-radius:8px;",
      "background:none;color:inherit;cursor:pointer;font:inherit}",
      ".tml-nps-score:hover{background:#2563eb;border-color:#2563eb;color:#fff}",
      ".tml-nps-legend{display:flex;justify-content:space-between;font-size:12px;color:#6b7280;margin-bottom:8px}",
      ".tml-nps-picked{width:44px;height:44px;margin:0 auto 12px;display:flex;align-items:center;justify-content:center;",
      "border-radius:10px;background:#2563eb;color:#fff;font-size:18px;font-weight:700}",
      ".tml-thanks{text-align:center;padding:16px 0}",
      ".tml-thanks-mark{width:44px;height:44px;margin:0 auto 10px;display:flex;align-items:center;justify-content:center;",
      "border-radius:50%;background:#16a34a;color:#fff;font-size:22px}",
      "@media (prefers-color-scheme:dark){",
      "#tml-dialog,.tml-inline{background:#1a1f26;color:#e6e8ea}",
      ".tml-inline{border-color:#2a313a}",
      "#tml-dialog textarea,#tml-dialog input[type=text],#tml-dialog input[type=email],#tml-dialog input[type=file],",
      ".tml-inline textarea,.tml-inline input[type=text],.tml-inline input[type=email],.tml-inline input[type=file]",
      "{border-color:#2a313a}",
      ".tml-secondary{border-color:#2a313a}",
      ".tml-star{color:#3a4149}",
      ".tml-star-on{color:#f59e0b}",
      ".tml-nps-score{border-color:#2a313a}",
      ".tml-record{border-color:#3b82f6;background:rgba(59,130,246,.1)}",
      ".tml-record:hover{background:rgba(59,130,246,.18)}",
      ".tml-record-label,.tml-chip-remove{color:#3b82f6}",
      ".tml-chip{background:rgba(59,130,246,.12)}",
      ".tml-hint,.tml-nps-legend,.tml-record-hint{color:#9aa2ab}",
      "}"
    ].join("");
    var style = document.createElement("style");
    style.id = "tml-styles";
    style.textContent = css;
    document.head.appendChild(style);
  }
})();
