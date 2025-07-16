#!/bin/bash

# --- توقف اسکریپت در صورت بروز خطا ---
set -e

echo "👑 MOHAMMAD REZA MORADI"
echo "==============================="
echo " VPN Bot Installation Manager (v2)"
echo "==============================="
echo "1) Install / Re-install"
echo "2) Remove"
read -p "Choose an option (1 or 2): " choice

# --- بخش حذف کامل ربات ---
if [ "$choice" == "2" ]; then
    echo "Deactivating and removing bot..."
    systemctl stop vpn_bot 2>/dev/null || true
    systemctl disable vpn_bot 2>/dev/null || true
    (crontab -l 2>/dev/null | grep -v "/root/monitor_backhaul.sh") | crontab -
    
    # حذف فایل‌های سیستمی، اسکریپت‌ها و فایل کنترلی
    rm -f /etc/systemd/system/vpn_bot.service
    rm -f /root/monitor_backhaul.sh
    rm -f /root/vpn_bot.py
    rm -f /root/autorestart.enabled # حذف فایل کنترلی
    rm -rf /root/venv_bot
    
    systemctl daemon-reload
    echo "✅ Bot and all its components removed successfully."
    exit 0
fi

if [ "$choice" != "1" ]; then
    echo "❌ Invalid option. Exiting."
    exit 1
fi

# --- دریافت اطلاعات از کاربر ---
read -p "🔐 Enter your Telegram Bot Token: " BOT_TOKEN
read -p "🆔 Enter your numeric Admin ID: " ADMIN_ID

# --- نصب نیازمندی‌های سیستم ---
echo "📦 Installing dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv curl

# --- ساخت محیط مجازی پایتون ---
echo "🧪 Creating a virtual environment..."
cd /root
python3 -m venv venv_bot
source /root/venv_bot/bin/activate
pip install --upgrade pip
pip install python-telegram-bot==21.3

# --- ساخت اسکریپت پایتون ربات ---
echo "📝 Creating /root/vpn_bot.py..."
cat > /root/vpn_bot.py <<EOF
import os
import subprocess
import re
from pathlib import Path
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, filters

BOT_TOKEN = os.environ.get("BOT_TOKEN")
ADMIN_ID = int(os.environ.get("ADMIN_ID"))
RESTART_FLAG_FILE = Path("/root/autorestart.enabled")

# --- دکمه های جدید برای مدیریت ریستارت خودکار ---
main_keyboard = ReplyKeyboardMarkup(
    [
        ["🔄 ریستارت بک‌هال", "📊 وضعیت بک‌هال"],
        ["⏱ آپتایم سرور", "📶 پینگ"],
        ["🚨 آخرین خطای بکهال"],
        ["✅ فعال کردن ریستارت خودکار"],
        ["🚫 غیرفعال کردن ریستارت خودکار"],
        ["❌ راهنمای حذف"]
    ],
    resize_keyboard=True
)

async def check_admin(update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
    if update.effective_user.id != ADMIN_ID:
        await update.message.reply_text("⛔ شما اجازه دسترسی به این ربات را ندارید.")
        return False
    return True

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_admin(update, context): return
    await update.message.reply_text("سلام! به پنل مدیریت سرور خوش آمدید. لطفاً یک گزینه را انتخاب کنید:", reply_markup=main_keyboard)

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_admin(update, context): return

    text = update.message.text
    command_output = ""
    error_output = ""

    try:
        if text == "✅ فعال کردن ریستارت خودکار":
            RESTART_FLAG_FILE.touch()
            command_output = "✅ قابلیت ریستارت خودکار سرویس فعال شد."

        elif text == "🚫 غیرفعال کردن ریستارت خودکار":
            if RESTART_FLAG_FILE.exists():
                RESTART_FLAG_FILE.unlink()
                command_output = "🚫 قابلیت ریستارت خودکار غیرفعال شد."
            else:
                command_output = "ℹ️ قابلیت ریستارت خودکار از قبل غیرفعال بوده است."

        elif text == "🔄 ریستارت بک‌هال":
            # ... (بقیه دستورات بدون تغییر باقی می‌مانند)
            result = subprocess.run(["systemctl", "restart", "backhaul"], capture_output=True, text=True, check=True)
            status_result = subprocess.run(["systemctl", "status", "backhaul", "--no-pager", "-n", "10"], capture_output=True, text=True)
            command_output = f"✅ بک‌هال با موفقیت ریستارت شد.\n📄 وضعیت فعلی:\n\n{status_result.stdout}"

        elif text == "📊 وضعیت بک‌هال":
            log_file = "/tmp/backhaul_status.log"
            with open(log_file, "w") as f:
                subprocess.run(["journalctl", "-u", "backhaul", "--no-pager", "-n", "20"], stdout=f, text=True)
            with open(log_file, "rb") as f:
                await context.bot.send_document(chat_id=ADMIN_ID, document=f, filename="backhaul_status.log", caption="📄 وضعیت سرویس بک‌هال (آخرین ۲۰ لاگ)")
            return
        
        elif text == "⏱ آپتایم سرور":
            result = subprocess.run(["uptime", "-p"], capture_output=True, text=True, check=True)
            command_output = f"⏱ آپتایم سرور:\n{result.stdout.strip()}"

        elif text == "📶 پینگ":
            result = subprocess.run(["ping", "-c", "4", "1.1.1.1"], capture_output=True, text=True, check=True)
            command_output = f"📶 نتیجه پینگ به 1.1.1.1:\n\n{result.stdout}"

        elif text == "🚨 آخرین خطای بکهال":
            cmd = ["journalctl", "-u", "backhaul", "--no-pager", "-n", "200", "--since", "2 hours ago"]
            output = subprocess.check_output(cmd, text=True)
            errors = re.findall(r".*(error|fail|critical|unauthorized|refused|disconnect).*", output, re.IGNORECASE)
            if errors:
                command_output = "🚨 آخرین خطاهای یافت شده:\n\n" + "\\n".join(errors[-10:])
            else:
                command_output = "✅ هیچ خطای قابل توجهی در ۲ ساعت گذشته یافت نشد."

        elif text == "❌ راهنمای حذف":
            command_output = "برای حذف کامل ربات، اسکریپت نصب را مجدداً اجرا کرده و گزینه 2 (Remove) را انتخاب کنید."
        
        else:
            command_output = "❓ دستور ناشناخته است. لطفاً از دکمه‌های زیر استفاده کنید."

    except Exception as e:
        error_output = f"❌ خطای داخلی در ربات:\n\n{str(e)}"

    if error_output:
        await update.message.reply_text(error_output[:4000])
    elif command_output:
        await update.message.reply_text(command_output[:4000])


if __name__ == '__main__':
    if not BOT_TOKEN or not ADMIN_ID:
        print("❌ Error: BOT_TOKEN or ADMIN_ID is not set in the environment.")
        exit(1)
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), handle_message))
    print("🤖 Bot is running...")
    app.run_polling()
EOF

# --- ساخت اسکریپت مانیتورینگ ---
echo "📝 Creating /root/monitor_backhaul.sh..."
cat > /root/monitor_backhaul.sh <<EOM
#!/bin/bash
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$ADMIN_ID"
HOSTNAME=\$(hostname)
TMP_LOG="/tmp/backhaul_scan.log"
RESTART_FLAG_FILE="/root/autorestart.enabled"

CRITICAL_ERRORS="(failed to dial|control channel has been closed|unauthorized|connection refused|fatal|panic)"
WARNING_ERRORS="(warn|timeout|disconnect|retry)"

journalctl -u backhaul --since "5 minutes ago" --no-pager > "\$TMP_LOG"

if grep -qEi "\$CRITICAL_ERRORS" "\$TMP_LOG"; then
    ERROR_MSG=\$(grep -Ei "\$CRITICAL_ERRORS" "\$TMP_LOG" | tail -n 5)

    # --- بررسی فعال بودن ریستارت خودکار ---
    if [ -f "\$RESTART_FLAG_FILE" ]; then
        # ریستارت خودکار فعال است
        curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
            -d chat_id="\$CHAT_ID" -d parse_mode="Markdown" \\
            -d text="🚨 *خطای بحرانی* در سرویس بک‌هال روی سرور *\$HOSTNAME*! در حال ریستارت خودکار..."

        systemctl restart backhaul
        sleep 5
        
        AFTER_RESTART_LOG=\$(journalctl -u backhaul --no-pager -n 15)
        curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
            -d chat_id="\$CHAT_ID" -d parse_mode="Markdown" \\
            -d text="✅ سرویس ریستارت شد. *لاگ‌های جدید:*
\`\`\`
\$AFTER_RESTART_LOG
\`\`\`"
    else
        # ریستارت خودکار غیرفعال است
        curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
            -d chat_id="\$CHAT_ID" -d parse_mode="Markdown" \\
            -d text="🚨 *خطای بحرانی* در سرویس بک‌هال روی سرور *\$HOSTNAME*!
*ریستارت خودکار غیرفعال است.* لطفاً به صورت دستی بررسی کنید.
*خطاها:*
\`\`\`
\$ERROR_MSG
\`\`\`"
    fi
fi
EOM

chmod +x /root/monitor_backhaul.sh

# --- افزودن Cronjob ---
echo "📅 Adding cronjob for monitor_backhaul.sh..."
(crontab -l 2>/dev/null | grep -v "/root/monitor_backhaul.sh") | { cat; echo "*/5 * * * * /root/monitor_backhaul.sh >/dev/null 2>&1"; } | crontab -

# --- فعال کردن ریستارت خودکار به صورت پیش‌فرض ---
echo "🔵 Enabling auto-restart by default..."
touch /root/autorestart.enabled

# --- ساخت سرویس Systemd برای ربات ---
echo "⚙️ Creating systemd service..."
cat > /etc/systemd/system/vpn_bot.service <<EOF
[Unit]
Description=VPN Management Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment="BOT_TOKEN=$BOT_TOKEN"
Environment="ADMIN_ID=$ADMIN_ID"
ExecStart=/root/venv_bot/bin/python /root/vpn_bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# --- فعال‌سازی و اجرای نهایی سرویس ---
systemctl daemon-reload
systemctl enable vpn_bot
systemctl restart vpn_bot

echo "✅ The bot was successfully installed and started."
echo "ℹ️ Auto-restart feature is now ENABLED by default. You can control it from the bot."
