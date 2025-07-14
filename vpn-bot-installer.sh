echo " MOHAMMADREZA MORADI "
echo "==============================="
echo " VPN Bot Installation Manager"
echo "==============================="
echo "1) Install"
echo "2) Remove"
read -p "Choose an option (1 or 2): " choice

if [ "$choice" == "2" ]; then
    echo "Removing bot..."
    systemctl stop vpn_bot
    systemctl disable vpn_bot
    rm -f /etc/systemd/system/vpn_bot.service
    rm -rf /root/venv_bot /root/vpn_bot.py
    systemctl daemon-reexec
    echo "✅ Bot removed successfully."
    exit 0
elif [ "$choice" != "1" ]; then
    echo "❌ Invalid option. Exiting."
    exit 1
fi

# اگر install انتخاب شده بود ادامه بده:
read -p "🔐 Telegram Bot Token : " BOT_TOKEN
read -p "🆔 Admin numeric ID: " ADMIN_ID

echo "📦 Installing dependencies..."
apt update -y && apt install -y python3 python3-pip python3-venv curl

echo "🧪 Creating a virtual environment..."
cd /root
python3 -m venv venv_bot
source /root/venv_bot/bin/activate
pip install --upgrade pip
pip install python-telegram-bot

echo "📝 File creation /root/vpn_bot.py..."
cat > /root/vpn_bot.py <<EOF
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, filters
import subprocess

BOT_TOKEN = "$BOT_TOKEN"
ADMIN_ID = $ADMIN_ID

main_keyboard = ReplyKeyboardMarkup(
    [["🔄 ریستارت بک‌هال"], ["📊 وضعیت بک‌هال"], ["⏱ آپتایم سرور"], ["📶 پینگ"], ["❌ حذف ربات"],
  ["🚨 آخرین خطای بکهال"]],
    resize_keyboard=True
)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        await update.message.reply_text("⛔ شما اجازه دسترسی ندارید.")
        return
    await update.message.reply_text("سلام! یکی از گزینه‌ها رو انتخاب کن:", reply_markup=main_keyboard)

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        await update.message.reply_text("⛔ شما اجازه استفاده ندارید.")
        return
    text = update.message.text
    if text == "🔄 ریستارت بک‌هال":
        restart = subprocess.run(["systemctl", "restart", "backhaul"], capture_output=True)
        if restart.returncode == 0:
            status = subprocess.run(["systemctl", "status", "backhaul", "--no-pager", "-n", "10"], capture_output=True, text=True)
            status_text = status.stdout or "وضعیت قابل دریافت نیست."
            await update.message.reply_text("✅ بک‌هال ریستارت شد.\n📄 وضعیت:\n\n" + status_text[:4000])
        else:
            await update.message.reply_text("❌ خطا در ریستارت:\n" + restart.stderr.decode())
    elif text == "📊 وضعیت بک‌هال":
        log_file = "/tmp/backhaul_status.log"
        with open(log_file, "w") as f:
            subprocess.run(["journalctl", "-u", "backhaul", "--no-pager", "-n", "100"], stdout=f)
        with open(log_file, "rb") as f:
            await context.bot.send_document(chat_id=ADMIN_ID, document=f, filename="backhaul_status.log", caption="📄 وضعیت بک‌هال (آخرین ۱۰۰ خط لاگ):")
    elif text == "📶 پینگ":
        result = subprocess.run(["ping", "-c", "4", "1.1.1.1"], capture_output=True, text=True)
        await update.message.reply_text(f"📶 نتیجه پینگ:\n\n{result.stdout[:4000]}")
        elif text == "⏱ آپتایم سرور":
    uptime = subprocess.run(["uptime", "-p"], capture_output=True, text=True)
    await update.message.reply_text(f"⏱ آپتایم سرور:\n{uptime.stdout.strip()}")

elif text == "🚨 آخرین خطای بکهال":
    log_file = "/root/backhaul.json"  # اگر لاگ جای دیگه‌ست مسیرشو تغییر بده
    last_error = subprocess.run(['grep', '-E', 'ERROR|WARN', log_file], capture_output=True, text=True)
    if last_error.stdout:
        await update.message.reply_text(f"🚨 آخرین خطای ثبت‌شده:\n\n{last_error.stdout.strip().splitlines()[-1]}")
    else:
        await update.message.reply_text("✅ هیچ خطایی در لاگ پیدا نشد.")
    elif text == "❌ حذف ربات":
        await update.message.reply_text("♻️ ربات در حال حذف از سیستم است...")
        subprocess.run(["systemctl", "stop", "vpn_bot"])
        subprocess.run(["systemctl", "disable", "vpn_bot"])
        subprocess.run(["rm", "-f", "/etc/systemd/system/vpn_bot.service"])
        subprocess.run(["rm", "-f", "/root/vpn_bot.py"])
        subprocess.run(["rm", "-rf", "/root/venv_bot"])
        subprocess.run(["systemctl", "daemon-reload"])
        await update.message.reply_text("✅ ربات حذف شد. برای نصب مجدد اسکریپت را دوباره اجرا کنید.")
    else:
        await update.message.reply_text("❓ دستور ناشناخته. لطفاً از دکمه‌ها استفاده کن.")

if __name__ == '__main__':
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), handle_message))
    print("🤖 Bot is running...")
    app.run_polling()
EOF

echo "⚙️ Service creation systemd..."
cat > /etc/systemd/system/vpn_bot.service <<EOF
[Unit]
Description=VPN Telegram Bot
After=network.target

[Service]
WorkingDirectory=/root
ExecStart=/root/venv_bot/bin/python /root/vpn_bot.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpn_bot
systemctl restart vpn_bot

echo "✅ The robot was successfully installed and running.!"