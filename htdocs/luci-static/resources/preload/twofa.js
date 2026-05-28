'use strict';
'require baseclass';
'require rpc';
'require ui';

var POLL_INTERVAL = 30000;

var callStatus = rpc.declare({
	object: 'luci.twofa',
	method: 'status',
	expect: { '': {} }
});

var callVerify = rpc.declare({
	object: 'luci.twofa',
	method: 'verify',
	params: [ 'token' ],
	expect: { '': {} }
});

return baseclass.extend({
	__init__: function() {
		var self = this;
		self.modal = null;
		self.enabled = false;
		self.verified = true;

		try { self.refresh(); } catch (_e) {}
		setInterval(function() {
			try { self.refresh(); } catch (_e) {}
		}, POLL_INTERVAL);
	},

	refresh: function() {
		var self = this;
		return callStatus().then(function(s) {
			s = s || {};
			self.enabled  = !!s.enabled;
			self.verified = !!s.verified;
			if (self.enabled && !self.verified) {
				self.showModal();
			} else {
				self.hideModal();
			}
		}).catch(function() { /* rpcd not ready yet; try again on next tick */ });
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

		var errorMsg = E('div', {
			'style': 'color:#ff4444;margin-top:10px;min-height:20px;'
		});

		var btn;
		var submit = function() {
			var code = (input.value || '').replace(/\s+/g, '');
			if (!/^\d{6}$/.test(code)) {
				errorMsg.innerText = _('Please enter a 6-digit code');
				return;
			}
			btn.disabled = true;
			errorMsg.innerText = _('Verifying...');

			callVerify(code).then(function(res) {
				btn.disabled = false;
				if (res && res.success) {
					self.verified = true;
					self.hideModal();
					window.location.reload();
				} else {
					errorMsg.innerText = _('Invalid verification code');
					input.value = '';
					input.focus();
				}
			}).catch(function() {
				btn.disabled = false;
				errorMsg.innerText = _('Verification failed, please try again');
				input.focus();
			});
		};

		btn = E('button', {
			'class': 'btn cbi-button-action',
			'click': submit
		}, _('Verify'));

		this.modal = ui.showModal(_('Two-Factor Authentication'), [
			E('p', {}, _('Please enter your 6-digit TOTP code to continue.')),
			E('div', { 'class': 'cbi-section-node' }, [ input ]),
			errorMsg,
			E('div', { 'class': 'right' }, [ btn ])
		]);

		document.body.style.overflow = 'hidden';

		try { input.focus(); } catch (_e) {}

		input.addEventListener('keypress', function(e) {
			if (e.key === 'Enter') {
				e.preventDefault();
				submit();
			}
		});
	}
});
