"""Reproduce the checked 2025 city profile snapshot. Sources live with each record."""
import json
from pathlib import Path

def source(title,url):return dict(title=title,url=url)
def industry(name,value,gdp):return dict(name=name,percent=round(value/gdp*100,2))
def profile(code,gdp,sectors,consumption,industries,sources,scope='城镇居民'):
 return dict(code=code,year=2025,gdp=gdp,sectors=sectors,annualConsumption=consumption,
 consumptionScope=scope,industries=industries,sources=sources)

profiles=[
 profile('110000',52073.4,[0.2,13.8,86.0],54122,
  [industry('信息传输、软件和信息技术服务',12192.4,52073.4),industry('金融业',8668.2,52073.4)],
  [source('北京市2025年统计公报','https://www.beijing.gov.cn/zhengce/zhengcefagui/202603/t20260325_4565678.html'),
   source('北京2025年经济运行情况','https://www.beijing.gov.cn/gongkai/shuju/sjjd/202601/t20260121_4452114.html')]),
 profile('310000',56708.71,[0.2,20.5,79.3],57076,
  [industry('金融业',8979.66,56708.71),dict(name='信息服务与先进制造',percent=None)],
  [source('上海2025年经济运行情况','https://tjj.sh.gov.cn/tjxw/20260120/d3f4918a77484c77bed173db6aaef33c.html'),
   source('上海2025年居民收支','https://www.shanghai.gov.cn/nw48810/20260203/2bed33e23b324e27ae846d3a88bade53.html'),
   source('上海2025年金融业数据','https://jrj.sh.gov.cn/ZXYW178/20260331/7cd814fd488f4718b54c0b578ccc8be0.html')]),
 profile('440100',32039.46,[0.99,24.06,74.95],51860,
  [industry('批发和零售业',3920.09,32039.46),industry('金融业',3220.99,32039.46),industry('交通运输、仓储和邮政',2022.03,32039.46)],
  [source('广州市2025年统计公报','https://tjj.gz.gov.cn/zzfwzq/tjkx/content/post_10804061.html')]),
 profile('440300',38731.80,[0.1,37.4,62.5],53548,
  [dict(name='高技术制造、装备制造',percent=None),dict(name='信息服务、现代服务业',percent=None)],
  [source('深圳市2025年统计公报','https://www.sz.gov.cn/cn/xxgk/zfxxgj/tjsj/tjgb/content/post_12805133.html'),
   source('深圳2025年经济运行情况','https://www.sz.gov.cn/cn/xxgk/zfxxgj/tjsj/tjfx/content/post_12624917.html')],scope='全体居民'),
 profile('330100',23011,[1.7,24.5,73.8],59484,
  [industry('金融业',2741,23011),industry('批发和零售业',1650,23011),industry('交通运输、仓储和邮政',707,23011),dict(name='信息软件与数字经济',percent=None)],
  [source('杭州市2025年统计公报（杭州日报刊载）','https://hzdaily.hangzhou.com.cn/hzrb/2026/04/30/article_detail_1_20260430A065.html')]),
 profile('510100',24763.6,[2.2,27.9,69.9],37100,
  [industry('金融业',2405.2,24763.6),industry('批发和零售业',2343.6,24763.6),industry('信息传输、软件和信息技术服务',2136.1,24763.6)],
  [source('成都市2025年统计公报（成都日报刊载，新浪转载）','https://finance.sina.com.cn/jjxw/2026-04-15/doc-inhupeis3814625.shtml'),
   source('成都2025年经济运行情况','https://news.chengdu.cn/2026/0123/6972d9f555808711169d4361.shtml')])]
root=Path(__file__).resolve().parents[1]
(root/'assets/cities/profiles.json').write_text(json.dumps(profiles,ensure_ascii=False,indent=2))
