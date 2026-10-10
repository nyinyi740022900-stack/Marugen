# Customer order requests / remarks

မွမ်းမံသည့်နေ့: 2026-10-10

## Customer အသုံးပြုပုံ

Checkout ရဲ့ Order Summary အောက်မှာ **Order requests / remarks (optional)** ရေးကွက်ကို ထည့်ထားပါတယ်။ မရောက်ခင် ဖုန်းဆက်ပေးရန်၊ တံခါးဘဲလ်နှိပ်ပေးရန် စတဲ့ ဆိုင်ကိုပြောလိုသော အချက်တွေကို ရေးနိုင်ပါတယ်။ မလိုအပ်ရင် ဗလာထားပြီး ငွေပေးချေနိုင်ပါတယ်။

မြန်မာစာနဲ့ စာကြောင်းခွဲရေးနိုင်ပြီး Unicode စာလုံး 500 အထိ လက်ခံပါတယ်။ ကျော်နေပါက ပြင်ဆင်ရန် ပြပြီး Pay ကို ခေတ္တပိတ်ထားပါတယ်။ Payment setup မအောင်မြင်လို့ ပြန်ကြိုးစားချိန် မှတ်ချက်ကို ပြင်နိုင်ပါတယ်။ နောက်ကျလာတဲ့ အရင် request က နောက်ဆုံးမှတ်ချက်ကို ပြန်ဖုံးမသွားစေရန် version စစ်ထားပါတယ်။

Order တင်ပြီးနောက် customer နဲ့ admin နှစ်ဖက်လုံးရဲ့ **Order Detail → CUSTOMER REQUESTS / REMARKS** မှာ ပြန်ဖတ်နိုင်ပါတယ်။ Admin order list မှာ မှတ်ချက်ပါတဲ့ order ကို **Customer requests added** လို့ ဖော်ပြပါတယ်။ မှတ်ချက်မပါသော အရင် order တွေမှာ ဒီအပိုင်းကို မပြပါ။

## Backend နှင့် app update အစီအစဉ်

လက်ရှိ source code ကို ပြင်ထားခြင်းဖြစ်ပြီး live backend ကို မပြောင်းရသေးပါ။ အသုံးပြုသူများအတွက် အလုပ်လုပ်စေရန် အောက်ပါအစီအစဉ်အတိုင်း update လုပ်ရပါမယ်။

1. Live database ရဲ့ migration history ကို စစ်ပြီး `supabase/migrations/0050_customer_order_remarks.sql` ကို apply လုပ်ပါ။ ယခင် pending migration များကို တစ်ခါတည်း မစစ်ဘဲ apply မလုပ်ပါနှင့်။
2. Updated `create-payment-intent` Edge Function ကို deploy လုပ်ပါ။ Database column မရှိသေးဘဲ function ကို အရင် deploy မလုပ်ပါနှင့်။
3. App update ကို စမ်းသပ်ပြီး ဖြန့်ချိပါ။ အရင် function က remarks payload ကို လျစ်လျူရှုနိုင်သဖြင့် backend မပြင်မီ app ကို မဖြန့်ပါနှင့်။
4. Test environment မှာ မှတ်ချက်ပါသော order၊ ဗလာ order၊ payment retry နှင့် မှတ်ချက်ဖျက်ခြင်းတို့ကို စစ်ပါ။ Customer နှင့် admin နှစ်ဖက်စလုံးမှာ စာသားမှန်ကန်ကြောင်း အတည်ပြုပါ။

အခု feature မှာ checkout မပြီးမီ မှတ်ချက်ထည့်ခြင်း၊ သိမ်းခြင်းနှင့် order detail မှာ ဖတ်ခြင်း ပါဝင်ပါတယ်။ Order တင်ပြီးနောက် မှတ်ချက်ပြန်ပြင်ခြင်း၊ invoice / packing slip ထဲ ပုံနှိပ်ခြင်း မပါဝင်ပါ။

## စစ်ဆေးထားမှု

- Remarks normalization၊ စာလုံးကန့်သတ်ချက်၊ မြန်မာစာ၊ payment payload၊ order parsing / display နှင့် Light / Dark narrow-screen UI အတွက် Flutter tests ရေးထားပါတယ်။ နောက်ဆုံး revision ပြင်ဆင်ပြီး full Flutter suite 62 ခုလုံး အောင်မြင်ပါတယ်။
- Server helper tests 4 ခု အောင်မြင်ပါတယ်။ Reordered retry၊ မှတ်ချက်ဖျက်ခြင်းနှင့် invalid revision ကို စစ်ပါတယ်။ Atomic database update guard ကို code review ဖြင့် စစ်ထားပြီး live database concurrency integration test မလုပ်ရသေးပါ။
- Updated Edge Function TypeScript type-check အောင်မြင်ပါတယ်။
- Live payment / database migration / Edge Function deployment မလုပ်ရသေးပါ။
