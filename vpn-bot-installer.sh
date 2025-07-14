#!/bin/bash

echo "🔧 Starting the backhaul robot installation"

read -p "🤖 Telegram Bot Token: " BOT_TOKEN
read -p "👤 Admin numeric ID (Admin ID): " ADMIN_ID

echo "📦 Install the required tools..."
apt update -y && apt install -y python3 python3-pip python3-venv curl

echo "🧪 Creating a virtual environment..."
cd /root
python3 -m venv venv_bot
source /root/venv_bot/bin/activate
pip install --upgrade pip
pip install python-telegram-bot

echo "📝 File creation vpn_bot.py..."
cat > /root/vpn_bot.py <<EOF

from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, filters
import subprocess
import os
from datetime import datetime

BOT_TOKEN = "YOUR_BOT_TOKEN"
ADMIN_ID = YOUR_ADMIN_ID

main_keyboard = ReplyKeyboardMarkup(
    [["🔄 ریستارت بک‌هال", "📊 وضعیت بک‌هال"],
     ["🧠 منابع سرور", "🌐 تست اتصال دامنه"],
     ["📶 پینگ", "❌ حذف کامل"]],
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
        subprocess.run(["systemctl", "restart", "backhaul"])
        log_path = "/var/log/backhaul_restarts.log"
        with open(log_path, "a") as f:
            f.write(f"{datetime.now()} - Backhaul restarted by admin\n")
        await update.message.reply_text("✅ بک‌هال ریستارت شد.")

    elif text == "📊 وضعیت بک‌هال":
        log_file = "/tmp/backhaul_status.log"
        with open(log_file, "w") as f:
            subprocess.run(["journalctl", "-u", "backhaul", "--no-pager", "-n", "100"], stdout=f)
        with open(log_file, "rb") as f:
            await context.bot.send_document(chat_id=ADMIN_ID, document=f, filename="backhaul_status.log")

    elif text == "🧠 منابع سرور":
        result = subprocess.run(["top", "-b", "-n", "1"], capture_output=True, text=True)
        await update.message.reply_text(f"📊 منابع سرور:

{result.stdout[:4000]}")

    elif text == "🌐 تست اتصال دامنه":
        await update.message.reply_text("لطفاً آدرس دامنه را ارسال کن:")

    elif text.startswith("http"):
        ping = subprocess.run(["ping", "-c", "3", text], capture_output=True, text=True)
        await update.message.reply_text(f"نتیجه پینگ:
{ping.stdout or ping.stderr}")

    elif text == "📶 پینگ":
        ping = subprocess.run(["ping", "-c", "4", "8.8.8.8"], capture_output=True, text=True)
        await update.message.reply_text(ping.stdout)

    elif text == "❌ حذف کامل":
        await update.message.reply_text("در حال حذف ربات و فایل‌های مربوطه...")
        os.system("systemctl stop vpn_bot")
        os.system("systemctl disable vpn_bot")
        os.remove("/etc/systemd/system/vpn_bot.service")
        os.remove("/root/vpn_bot.py")
        os.system("rm -rf /root/venv_bot")
        await update.message.reply_text("✅ ربات و فایل‌های آن حذف شدند. لطفاً دستی این ترمینال را ببندید.")

    else:
        await update.message.reply_text("❓ دستور ناشناخته. لطفاً از کیبورد استفاده کن.")

if __name__ == '__main__':
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), handle_message))
    print("Bot is running...")
    app.run_polling()

EOF

sed -i "s/YOUR_BOT_TOKEN/${BOT_TOKEN}/g" /root/vpn_bot.py
sed -i "s/YOUR_ADMIN_ID/${ADMIN_ID}/g" /root/vpn_bot.py

echo "⚙️ ساخت سرویس systemd..."
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

echo "✅ نصب کامل شد. ربات در حال اجراست."
