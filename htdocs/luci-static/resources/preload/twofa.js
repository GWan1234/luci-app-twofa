'use strict';
'require baseclass';
'require request';
'require rpc';
'require ui';

var ALLOW_PREFIX = '/admin/services/twofa/';
var POLL_INTERVAL = 15000;

function isAllowedUrl(url) {
	if (!url) return false;
	return String(url).indexOf(ALLOW_PREFIX) !== -1;
}

function safeJson(res) {
	if (!res) return null;
	try { return (typeof res.json === 'function') ? res.json() : null; }
	catch (_e) { return null; }
}

return baseclass.extend({
	__init__: function() {
		var self = this;

		self.enabled = false;
		self.verified = true;

		if (request && typeof request.addInterceptor === 'function') {
			request.addInterceptor(function(res) {
				if (!self.enabled || self.verified) return res;
				var url = (res && res.url) ? res.url : '';
				if (isAllowedUrl(url)) return res;
				return Promise.reject(new Error('2FA Required'));
			});
		}

		if (rpc && typeof rpc.addInterceptor === 'function') {
			rpc.addInterceptor(function(msg, req) {
				if (!self.enabled || self.verified) return msg;
				var url = (req && req.xhr && req.xhr.responseURL) ? req.xhr.responseURL : '';
				if (isAllowedUrl(url)) return msg;
				return Promise.reject(new Error('2FA Required'));
			});
		}

		self.checkStatus();
		setInterval(function() { self.checkStatus(); }, POLL_INTERVAL);
	},

	httpGet: function(path) {
		if (request && typeof request.get === 'function') {
			return request.get(L.url(path), { cache: false });
		}
		return L.get(L.url(path));
	},

	httpPost: function(path, body) {
		if (request && typeof request.post === 'function') {
			return request.post(L.url(path), body);
		}
		return L.post(L.url(path), body);
	},

	checkStatus: function() {
		var self = this;
		self.httpGet('admin/services/twofa/status').then(function(res) {
			var status = safeJson(res);
			if (status && status.enabled) {
				self.enabled = true;
				self.verified = !!status.verified;
				if (!self.verified) self.showModal();
				else self.hideModal();
			} else {
				self.enabled = false;
				self.verified = true;
				self.hideModal();
			}
		}).catch(function() { /* swallow */ });
	},

	hideModal: function() {
		if (this.modal) {
			try { ui.hideModal(); } catch (_e) {}
			this.modal = null;
		}
		document.body.style.overflow = '';
	},

	showModal: function() {
		if (this.modal) return;
		var self = this;

		var input = E('input', {
			'class': 'cbi-input-text',
			'type': 'text',
			'maxlength': 6,
			'inputmode': 'numeric',
			'autocomplete': 'one-time-code',
			'placeholder': '000000',
			'style': 'font-size:24px;text-align:center;letter-spacing:5px;width:100%;'
		});

		var errorMsg = E('div', { 'style': 'color:#ff4444;margin-top:10px;min-height:20px;' });

		var btn = E('button', {
			'class': 'btn cbi-button-action',
			'click': function() {
				var code = (input.value || '').replace(/\s+/g, '');
				if (!/^\d{6}$/.test(code)) {
					errorMsg.innerText = _('Invalid format');
					return;
				}
				errorMsg.innerText = _('Verifying...');
				self.httpPost('admin/services/twofa/verify', { token: code }).then(function(res) {
					var data = safeJson(res);
					if (data && data.success) {
						self.verified = true;
						self.hideModal();
						location.reload();
					} else {
						errorMsg.innerText = _('Invalid verification code');
						input.value = '';
						input.focus();
					}
				}).catch(function() {
					errorMsg.innerText = _('Invalid verification code');
				});
			}
		}, _('Verify'));

		this.modal = ui.showModal(_('Two-Factor Authentication'), [
			E('p', {}, _('Please enter your 6-digit TOTP code to continue.')),
			E('div', { 'class': 'cbi-section-node' }, [ input ]),
			errorMsg,
			E('div', { 'class': 'right' }, [ btn ])
		]);

		document.body.style.overflow = 'hidden';
		input.focus();

		input.addEventListener('keypress', function(e) {
			if (e.key === 'Enter') {
				e.preventDefault();
				btn.click();
			}
		});
	}
});
