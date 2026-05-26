'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
    __init__: function() {
        var self = this;
        
        LuCI.request.addInterceptor(function(res) {
            if (self.enabled && !self.verified) {
                var url = res && res.url ? res.url : '';
                if (url.indexOf('/admin/services/twofa/') === -1 &&
                    url.indexOf('/admin/ubus') === -1) {
                    return Promise.reject(new Error('2FA Required'));
                }
            }
            return res;
        });

        this.checkStatus();
        
        // 挂载全局定时检查，处理多标签页同步
        setInterval(function() {
            self.checkStatus();
        }, 15000);
    },

    checkStatus: function() {
        var self = this;
        // 直接调用之前定义的 status API
        L.get(L.url('admin/services/twofa/status')).then(function(res) {
            var status = res.json();
            if (status && status.enabled) {
                self.enabled = true;
                self.verified = status.verified;
                if (!self.verified) {
                    self.showModal();
                } else if (self.modal) {
                    self.modal.close();
                    self.modal = null;
                    document.body.style.overflow = '';
                }
            } else {
                self.enabled = false;
                self.verified = true;
                if (self.modal) {
                    self.modal.close();
                    self.modal = null;
                    document.body.style.overflow = '';
                }
            }
        }).catch(function() {});
    },

    showModal: function() {
        if (this.modal) return;

        var self = this;
        var input = E('input', {
            'class': 'cbi-input-text',
            'type': 'text',
            'maxlength': 6,
            'placeholder': '000000',
            'style': 'font-size: 24px; text-align: center; letter-spacing: 5px; width: 100%;'
        });

        var errorMsg = E('div', { 'style': 'color: #ff4444; margin-top: 10px; min-height: 20px;' });

        this.modal = ui.showModal(_('Two-Factor Authentication'), [
            E('div', { 'class': 'cbi-section' }, [
                E('p', {}, _('Please enter your 6-digit TOTP code to continue.')),
                E('div', { 'class': 'cbi-section-node' }, [
                    input
                ]),
                errorMsg,
                E('div', { 'class': 'right' }, [
                    E('button', {
                        'class': 'btn cbi-button-action',
                        'click': function() {
                            var code = input.value;
                            if (code.length !== 6) {
                                errorMsg.innerText = _('Invalid format');
                                return;
                            }
                            errorMsg.innerText = _('Verifying...');
                            
                            L.post(L.url('admin/services/twofa/verify'), { token: code }).then(function(res) {
                                var data = res.json();
                                if (data && data.success) {
                                    self.verified = true;
                                    self.modal.close();
                                    self.modal = null;
                                    location.reload();
                                } else {
                                    errorMsg.innerText = _('Invalid verification code');
                                    input.value = '';
                                    input.focus();
                                }
                            });
                        }
                    }, _('Verify'))
                ])
            ])
        ], {
            'noClose': true // 强制禁止关闭
        });

        input.focus();
        
        // 禁用背景滚动
        document.body.style.overflow = 'hidden';
        
        // 监听 Enter 键
        input.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                input.parentElement.nextElementSibling.nextElementSibling.querySelector('button').click();
            }
        });
    }
});
