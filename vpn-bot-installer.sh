#!/bin/bash

echo "🔧 Start installing Riba"

read -p "🔐 Telegram Bot Token: " BOT_TOKEN
read -p " Numeric ID (Admin ID): " ADMIN_ID

echo "📦   Installing the necessary Python tools  ..."
apt update -y && apt install -y python3 python3-pip python3-venv curl

echo "🧪 Creating a virtual environment   ..."
cd /root
python3 -m venv venv_bot
source /root/venv_bot/bin/activate
pip install --upgrade pip
pip install python-telegram-bot

echo "📝 Construction File creation  vpn_bot.py..."
cat > /root/vpn_bot.py <<EOF
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, filters
import subprocess

BOT_TOKEN = "$BOT_TOKEN"
ADMIN_ID = $ADMIN_ID

main_keyboard = ReplyKeyboardMarkup(
    [["🔄 ریستارت بک‌هال", "📊 وضعیت بک‌هال"]],
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
            if len(status_text) > 4000:
                status_text = status_text[-4000:]
            await update.message.reply_text("✅ بک‌هال ریستارت شد.\\n📄 وضعیت:\\n\\n" + status_text)
        else:
            await update.message.reply_text("❌ خطا در ریستارت:\\n" + restart.stderr.decode())
    elif text == "📊 وضعیت بک‌هال":
        log_file = "/tmp/backhaul_status.log"
        with open(log_file, "w") as f:
            subprocess.run(["journalctl", "-u", "backhaul", "--no-pager", "-n", "100"], stdout=f)
        with open(log_file, "rb") as f:
            await context.bot.send_document(chat_id=ADMIN_ID, document=f, filename="backhaul_status.log", caption="📄 وضعیت بک‌هال (آخرین ۱۰۰ خط لاگ):")
    else:
        await update.message.reply_text("❓ دستور ناشناخته. لطفاً از کیبورد استفاده کن.")

if __name__ == '__main__':
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), handle_message))
    print("Bot is running...")
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

echo "✅ نصب کامل شد. ربات اجرا شد و در هر ریبوت خودش بالا میاد."
