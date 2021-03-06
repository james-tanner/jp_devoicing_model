## Calculate MFCCs and acoustic parameters from CSJ datasets
## James Tanner
## March 2021

import argparse
import parselmouth
import os
import re
import pandas as pd
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('inputCSV', help = "Path to the CSV containing phoneme information")
parser.add_argument('soundFiles', help = "Path to the CSJ soundfiles")
parser.add_argument('outputCSV', help = "Path to location for writing new CSV")
args = parser.parse_args()

df = pd.read_csv(args.inputCSV, sep = ",")

print("Dataset properties:\nRows:\t{}\nColumns:\t{}".format(len(df), len(df.columns)))

## Convert preceding consonant into voiced/voiceless categories
def GetPrevVoicing(x):
    voicing = np.where(np.in1d(x, ['c', 'cy', 'F', 'Fy', 'h', 'hy', 'k', 'ky', 'p', 'py',
            'S', 's', 'sy', 't', 'ty']), "voiceless",
            np.where(np.in1d(x, ['b', 'by', 'd', 'dy', 'g', 'gy', 'm', 'my', 'n', 'ny',
            'r', 'ry', 'v', 'w', 'y', 'Z', 'z', 'zy']), "voiced", "nan"))
    return voicing

## Determine following consonant voicing by mora
def GetFollowingVoicing(x):
    voicing = np.where(np.in1d(x, ['シ', 'カ', 'テ', 'ツ', 'ト', 'キ', 'ッ', 'ケ', 'タ',
            'ソ', 'ク', 'チ', 'コ', 'ス', 'ハ', 'サ', 'ぺ', 'セ', 'ホ', 'パ', 'へ',
            'ヒ', 'ピ', 'フ', 'プ', 'シャ', 'キュ', 'キョ', 'ヒャ', 'ショ', 'チュ',
            'シュ', 'ヒョ', 'トゥ', 'チャ', 'ティ', 'チョ', 'フォ', 'テュ', 'ツォ',
            'ツァ', 'スィ', 'ツェ', 'チェ']), "voiceless",
            np.where(np.in1d(x, ['マ', 'ド', 'ー', 'オ', 'ニ', 'レ', 'ラ', 'ガ', 'ワ',
            'モ', 'ン', 'ダ', 'ゴ', 'イ', 'ヨ', 'ボ', 'ジ', 'ズ', 'リ', 'ム', 'ナ',
            'ノ', 'ル', 'デ', 'メ', 'ネ', 'ギ', 'ブ', 'ゲ', 'ロ', 'ア', 'エ', 'ザ',
            'ビ', 'ヤ', 'ヌ', 'バ', 'ミ', 'ゾ', 'グ', 'ゼ', 'ウ', 'ユ', 'ジョ', 'ウォ',
            'ジュ', 'ビョ', 'ニュ', 'リョ', 'ミャ', 'ディ', 'ギョ', 'ニョ', 'ズィ',
            'ビュ', 'ジェ', 'ジャ', 'リュ', 'ドゥ', 'ギャ', 'ギュ', 'ニャ', 'リャ',
            'ミョ', 'ウェ', 'デゥ', 'ニェ']), "voiced",
            np.where(pd.isnull(x), "pause", "nan")))
    return voicing

## make a uniqueID column:
## since each PhonemeID is unique within a given file (TalkID),
## concatenate them for a unique mapping
df['ObsID'] = df['TalkID'] + "_" + df['PhonemeID']

## Create previous and following voicing columns
df['PrevVoicing'] = GetPrevVoicing(df['PrevPhoneme'].values)
df['FollowingVoicing'] = GetFollowingVoicing(df['FollowingMora'].values)

## declare empty MFCC columns
df['mfcc'] = np.nan
df['mfcc_shape'] = np.nan
df['mfcc_dur'] = np.nan

print("Measuring {} tokens across {} files".format(len(df), len(df['TalkID'].unique())))

## Start looping through audio files in the csv
for count, audio in enumerate(set(df.TalkID)):

	## Try reading the audio file (and skip if not found)
	try:
		sound = parselmouth.Sound(os.path.join(args.soundFiles, audio + ".wav"))
		print("Processing {} ({}/{})".format(audio, count + 1, len(set(df.TalkID))))

		## iterate through rows for that audio file
		for index, row in df.iterrows():
			if row["TalkID"] == audio:

				## extract each vowel and calculate MFCCs for them
				vowel = sound.extract_part(from_time = row['PhonemeStart'],
					                       to_time = row['PhonemeEnd'])
				mfcc_object = vowel.to_mfcc(number_of_coefficients=12)
				mfcc_arr = mfcc_object.to_array()
				
				## add the MFCCs and the shape to columns
				df.loc[index, 'mfcc'] = mfcc_arr
				df.loc[index, 'mfcc_shape'] = mfcc_arr.shape
				df.loc[index, 'mfcc_dur'] = mfcc_object.duration
			else:
				continue
	## Skip files that can't be found
	except parselmouth.PraatError as e:
		pass

## Write to CSV
df.to_csv(args.outputCSV, encoding = "UTF-16")
print("Done!")