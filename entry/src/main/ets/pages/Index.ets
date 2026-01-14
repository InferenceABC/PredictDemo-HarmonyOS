/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {modelLoad, modelPredict, modelLoadPredict} from '../model/Model';
import Logger from '../common/utils/Logger'
import { resourceManager } from '@kit.LocalizationKit'
import { fileIo } from '@kit.CoreFileKit'
import { CommonConstants } from '../common/constants/CommonConstants';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common, Want } from '@kit.AbilityKit';
import { fileIo as fs, ReadOptions, WriteOptions, Filter, ListFileOptions} from '@kit.CoreFileKit';
import { FunctionalButton } from '@kit.ScenarioFusionKit';

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Sigmoid 激活函数 (对应 Python: torch.sigmoid)
function sigmoid(x: number): number {
  return 1 / (1 + Math.exp(-x));
}

function generateGateResultString(out: Float32Array): string {
  if (!out || out.length === 0) return "错误：模型无输出";

  // 假设模型输出是 Logits (未经过 Sigmoid)
  // 如果你的 .ms 模型内部已经包含了 Sigmoid，这里就不需要再调 sigmoid 函数
  // 根据你提供的 Python 代码: nn.Linear -> ReLU -> Dropout -> Linear，最后没有 Sigmoid 层
  // 所以这里需要手动加 Sigmoid
  const logits = out[0];
  const prob = sigmoid(logits);
  const threshold = 0.5;
  const isCloud = prob >= threshold;

  let resultStr = "=== 文本路由决策 ===\n";
  resultStr += `Logits: ${logits.toFixed(4)}\n`;
  resultStr += `上云概率: ${(prob * 100).toFixed(2)}%\n`;
  resultStr += `阈值判定: ${threshold}\n`;
  resultStr += `------------------\n`;
  resultStr += `最终决策: ${isCloud ? "☁️ 发送至云端大模型" : "📱 留在端侧处理"}`;

  return resultStr;
}

function generateModelChoiceString(out: Float32Array): string {
  // 定义前4个模型对应的名称
  const modelNames = [
    'face_det_damofd_10g',
    'face_det_retina',
    'face_det_damofd_2.5g',
    'face_det_damofd_34g'
  ];

  // 1. 【安全检查】处理数组越界风险
  // 如果数组不存在，或者长度小于我们需要比较的模型数量（4个），直接返回错误信息
  if (!out || out.length < modelNames.length) {
    return `错误：模型输出长度不足 (需至少${modelNames.length}位，实际${out ? out.length : 0}位)`;
  }

  let maxScore = -Infinity;
  let bestModelName = "";
  const scoreStrings: string[] = [];

  // 2. 遍历前4个模型，收集分数并寻找最大值
  for (let i = 0; i < modelNames.length; i++) {
    const currentScore = out[i];
    const currentName = modelNames[i];

    // 格式化当前分数用于展示 (例如 "face_det_damofd: 0.8845")
    scoreStrings.push(`${currentName}: ${currentScore.toFixed(4)}`);

    // 更新最大值逻辑
    if (currentScore > maxScore) {
      maxScore = currentScore;
      bestModelName = currentName;
    }
  }

  // 3. 构建结果字符串
  // 第一行：用中文逗号连接所有分数详情
  const scoreLine = scoreStrings.join("\n");

  // 第二行：显示最终选择
  const choiceLine = `选择 ${bestModelName} 模型，分数为 ${maxScore.toFixed(4)}`;

  // 使用 \n 实现换行
  return scoreLine + '\n' + choiceLine;
}

// 1. 定义包含 ID 的模型元数据接口
interface EnhanceModelInfo {
  id: number;      // 新增：1-9 的固定 ID
  index: number;   // 张量中的索引
  name: string;    // 模型名称
  group: string;   // 组名描述
  desc: string;    // 描述
}

// 2. 获胜者信息类，也携带 ID
class WinnerInfo {
  id: number = 0;      // 新增 ID
  name: string = '';
  score: number = 0;
  desc: string = '';
  group: string = '';
}

/**
 * 生成多模型推荐排序字符串
 * @param out 模型输出的 Float32Array
 * @param enableThreshold 是否开启人脸检测阈值判断 (默认为 true)
 * true: 分数 >= 0.3 才能排第一，否则可能不显示或提示无效
 * false: 不管分数多低，人脸组的第一名强制排在总榜第一
 */
function generateEnhanceRankString(out: Float32Array, enableThreshold: boolean = false): string {

  // === 定义 9 个模型的固定 ID (1-9) 和索引映射 ===
  const models: EnhanceModelInfo[] = [
    // --- 人脸检测组 (ID 1-4) ---
    { id: 1, index: 0, name: '人脸检测-Damoyolo', group: '人脸检测', desc: '人脸检测器' },
    { id: 2, index: 1, name: '人脸检测-RetinaFace', group: '人脸检测', desc: '人脸检测器' },
    { id: 3, index: 2, name: '人脸检测-Damofd 2.5G', group: '人脸检测', desc: '轻量版' },
    { id: 4, index: 3, name: '人脸检测-Damofd 3.4G', group: '人脸检测', desc: '标准版' },

    // --- 图像调色组 (ID 5-6) ---
    { id: 5, index: 12, name: '图像调色-CSRNet', group: '图像调色', desc: '色彩增强' },
    { id: 6, index: 13, name: '图像调色-DeepLPFNet', group: '9图像调色', desc: '细节增强' },

    // --- 图像去噪组 (ID 7) ---
    { id: 7, index: 14, name: '图像去噪-NAFNet', group: '图像去噪', desc: '去噪' },

    // --- 人像美化组 (ID 8-9) ---
    { id: 8, index: 15, name: '人像美化-UNet', group: '11人像美化', desc: '美肤' },
    { id: 9, index: 16, name: '人像美化-FBBR', group: '11人像美化', desc: '塑形' }
  ];

  // 1. 【安全检查】
  if (!out || out.length <= 16) {
    return `错误：模型输出长度不足 (需至少17位，实际${out ? out.length : 0}位)`;
  }

  // 2. 【第一部分】构建原始分数详情 (显示 ID 1-9)
  let rawScoreLines: string[] = [];
  models.forEach(m => {
    // 格式: [ID:1] Damoyolo: 0.1234
    rawScoreLines.push(`[ID:${m.id}] ${m.name}: ${out[m.index].toFixed(4)}`);
  });
  const allScoresStr = "=== 原始分数 (ID 1-9) ===\n" + rawScoreLines.join("\n");


  // 3. 【第二部分】核心逻辑：各组内部选拔

  // ---------------------------------------------------------
  // 【A】人脸检测组 (ID 1-4) 选拔
  // ---------------------------------------------------------
  let faceWinner: WinnerInfo | null = null;
  let maxFaceScore = -Infinity;
  let bestFaceModel: EnhanceModelInfo | null = null;

  // 遍历前 4 个模型 (数组下标 0-3)
  for (let i = 0; i < 4; i++) {
    const m = models[i]; // 获取 ID 1-4 的模型元数据
    const score = out[m.index];
    if (score > maxFaceScore) {
      maxFaceScore = score;
      bestFaceModel = m;
    }
  }

  // 阈值判断逻辑
  if (bestFaceModel !== null) {
    const isScoreValid = maxFaceScore >= 0.3;

    // 如果 开启了阈值检查 且 分数不达标，则 faceWinner 为 null
    // 否则 (关闭阈值 或 分数达标)，选出胜者
    if (!enableThreshold || isScoreValid) {
      faceWinner = {
        id: bestFaceModel.id,
        name: bestFaceModel.name,
        score: maxFaceScore,
        desc: bestFaceModel.desc,
        group: bestFaceModel.group
      };
    }
  }

  // ---------------------------------------------------------
  // 【B】图像调色组 (ID 5 vs 6)
  // ---------------------------------------------------------
  let winner9: WinnerInfo;
  const m5 = models[4]; // CSRNet
  const m6 = models[5]; // DeepLPFNet
  const s5 = out[m5.index];
  const s6 = out[m6.index];

  if (s5 >= s6) {
    winner9 = { id: m5.id, name: m5.name, score: s5, desc: m5.desc, group: m5.group };
  } else {
    winner9 = { id: m6.id, name: m6.name, score: s6, desc: m6.desc, group: m6.group };
  }

  // ---------------------------------------------------------
  // 【C】图像去噪组 (ID 7)
  // ---------------------------------------------------------
  const m7 = models[6]; // NAFNet
  let winner10: WinnerInfo = {
    id: m7.id, name: m7.name, score: out[m7.index], desc: m7.desc, group: m7.group
  };

  // ---------------------------------------------------------
  // 【D】人像美化组 (ID 8 vs 9)
  // ---------------------------------------------------------
  let winner11: WinnerInfo;
  const m8 = models[7]; // UNet
  const m9 = models[8]; // FBBR
  const s8 = out[m8.index];
  const s9 = out[m9.index];

  if (s8 >= s9) {
    winner11 = { id: m8.id, name: m8.name, score: s8, desc: m8.desc, group: m8.group };
  } else {
    winner11 = { id: m9.id, name: m9.name, score: s9, desc: m9.desc, group: m9.group };
  }


  // 4. 【第三部分】总排序逻辑

  // 步骤 1: 对 3 个增强任务的胜者进行降序排序
  let enhanceList: WinnerInfo[] = [winner9, winner10, winner11];
  enhanceList.sort((a, b) => b.score - a.score);

  // 步骤 2: 构建最终列表
  let finalList: WinnerInfo[] = [];

  // 如果有人脸检测胜者 (根据上面的逻辑，可能是分数够高，或者是关闭了阈值限制)，排第一
  if (faceWinner !== null) {
    finalList.push(faceWinner);
  }

  // 追加增强模型
  finalList = finalList.concat(enhanceList);


  // 5. 【第四部分】构建结果字符串
  let choiceLines: string[] = [];
  choiceLines.push("=== 推荐执行顺序 ===");

  if (faceWinner === null && enableThreshold) {
    choiceLines.push("提示：未检测到有效人脸 (ID 1-4 分数均 < 0.3)");
  }

  for (let i = 0; i < finalList.length; i++) {
    const item = finalList[i];
    // 格式： 1. [ID:3] Damofd 2.5G: 0.8888
    choiceLines.push(`${i + 1}. [ID:${item.id}] ${item.name}+: ${item.score.toFixed(4)}`);
  }

  return allScoresStr + '\n\n' + choiceLines.join("\n");
}

@Entry
@Component
struct Index {
  @State currentMode: number = 0;

  @State fileNameShow: number = 0;
  @State photoShow: number = 0;
  @State textShow: number = 0;
  @State predictResultShow: number = 0;

  @State fileName: string = '';
  @State uris: Array<string> = [];
  @State textContent: string = '';
  @State predictText: string = '';

  // 任务 ID，用于标记当前运行的任务版本
  @State taskId: number = 0;
  // 切换模式的原子操作
  // 作用：切换模式的同时，立即作废正在运行的旧循环，并清理 UI
  switchMode(mode: number) {
    if (this.currentMode !== mode) {
      this.currentMode = mode;
      this.taskId++; // 核心：任务ID自增，旧循环检测到不一致会自动停止

      // 清理残留的显示状态
      this.uris = [];
      this.textContent = "";
      this.predictText = "";
      this.fileName = "";
      this.fileNameShow = 0;
      this.predictResultShow = 0;

      // 根据新模式设置 UI 显隐预设
      if (mode === 2) {
        this.photoShow = 0;
        this.textShow = 1;
      } else {
        this.photoShow = 1;
        this.textShow = 0;
      }
    }
  }

  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async predictInput(): Promise<void> {
    // 任务启动前，生成当前函数的“令牌”
    this.taskId++;
    const myTaskId = this.taskId; // 锁定当前 ID


    this.fileNameShow = 1;
    this.predictResultShow = 1;
    this.uris = [];
    this.textContent = '';

    let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    let filesDir = context.filesDir;

    // 显示与输入数据逻辑
    let embDir = '';
    let displayDir = '';
    switch (this.currentMode) {
      case 2 :
        embDir = filesDir + '/data_archive/251124_text_emb';
        displayDir = filesDir + '/data_archive/251124_text_raw';
        this.photoShow = 0;
        this.textShow = 1;
        break;
      default :
        embDir = filesDir +'/data_archive/250801_damo_emb';
        displayDir = filesDir +'/data_archive/250801_pictures';
        this.photoShow = 1;
        this.textShow = 0;
    }


    let listFileOption: ListFileOptions = {
      recursion: false,
      listNum: 0,
      filter: {
        suffix: [".txt"]
      }
    };
    let filenames = fs.listFileSync(embDir, listFileOption);

    // 模型选择，不同模式选择不通模型
    let resMgr: resourceManager.ResourceManager = this.context.getApplicationContext().resourceManager;

    let modelName = ''
    switch (this.currentMode) {
      case 0 :
        modelName = CommonConstants.MODEL_NAME_V4
        break;
      case 1 :
        modelName = CommonConstants.MODEL_NAME_V5
        break;
      case 2 :
        modelName = CommonConstants.MODEL_NAME_TXT
        break;
    }
    // let modelName = (this.currentMode === 2) ? CommonConstants.MODEL_NAME_TXT : CommonConstants.MODEL_NAME;
    let modelBuffer = await resMgr.getRawFileContent(modelName);
    let model = await modelLoad(modelBuffer.buffer.slice(0))

    let startTime = Date.now();
    for (let i = 0; i < filenames.length; i++) {

      // 循环守卫：如果当前 ID 不等于全局 ID，说明外界切换了模式或重启了任务
      if (myTaskId !== this.taskId) {
        console.warn(`[Task ${myTaskId}] 任务已因模式切换而终止`);
        return; // 直接退出函数
      }

      let vectorFileName = filenames[i];

      // --- A. 准备 UI 显示数据 (图片 或 文本) ---
      if (this.currentMode === 2) {
        // 文本模式：去 raw 文件夹找同名文件
        // 假设文件名一致，例如都是 "0.txt"
        this.fileName = vectorFileName;

        let rawTextPath = displayDir + '/' + vectorFileName;
        try {
          this.textContent = fs.readTextSync(rawTextPath, { encoding: 'utf-8' });
        } catch (e) {
          this.textContent = "未找到对应的原始文本文件: " + vectorFileName;
        }
      } else {
        // 图像模式：去 pictures 文件夹找对应图片
        // 假设 vector 是 "xxx.txt"，图片是 "xxx.png" 或无后缀
        let imageFileName = vectorFileName.replace(/\.txt$/, '');

        this.fileName = imageFileName;
        // 简单处理：尝试拼个路径
        let imagePath = 'file://' + displayDir + '/' + imageFileName;
        // 如果你的图片有后缀（如.png），需要在这里加上
        // let imagePath = 'file://' + displayDir + '/' + imageFileName + '.png';
        this.uris = [imagePath];
      }

      // --- B. 准备模型输入数据 (向量) ---
      let vectorPath = embDir + '/' + vectorFileName;
      let vectorContent = fs.readTextSync(vectorPath, { encoding: 'utf-8' });

      const numberArray: Array<number> = vectorContent.split(',').map(s => parseFloat(s));
      const inputArray: Float32Array = new Float32Array(numberArray);

      console.log(`[Mode ${this.currentMode}] Input shape: ${inputArray.length}`);


      // --- C. 模型推理 ---
      // 注意：inputArray.buffer 传给底层

      let output = await modelPredict(model, [inputArray.buffer]);
      let out = new Float32Array(output[0].getData());

      console.log("========= Output Data =====", out);


      // --- D. 结果展示 ---
      switch (this.currentMode) {
        case 0 :
          this.predictText = generateModelChoiceString(out);
          break;
        case 1 :
          this.predictText = generateEnhanceRankString(out);
          break;
        case 2 :
          this.predictText = generateGateResultString(out);
          break;
      }


      await sleep(1); // 慢一点，方便看清效果
    }
    let endTime = Date.now();
    console.info(`[Inference Profile] File Number: ${filenames.length}, Time: ${endTime - startTime}ms`);

  }

  async testOneInput(): Promise<void> {
    this.fileNameShow = 1;
    this.photoShow = 0;
    this.uris = [];
    this.predictResultShow = 1;


    let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    let filesDir = context.filesDir;
    let datasetDir = filesDir + '/data_archive/250801_damoyolo_emb'


    let listFileOption: ListFileOptions = {
      recursion: false,
      listNum: 0,
      filter: {
        suffix: [".txt"]
      }
    };
    let filenames = fs.listFileSync(datasetDir, listFileOption);

    // 模型加载
    let resMgr: resourceManager.ResourceManager = this.context.getApplicationContext().resourceManager;

    let modelName = CommonConstants.MODEL_NAME;
    if (this.currentMode === 2) {
      modelName = CommonConstants.MODEL_NAME_TXT; // 你的 Gate 模型
    }
    let modelBuffer = await resMgr.getRawFileContent(modelName);


    for (let i = 0; i < filenames.length; i++) {
      this.fileName = filenames[i].replace(/\.txt$/, '.png')

      let filePath = datasetDir + '/' + filenames[i]

      // 使用 fs.readTextSync，它直接返回解码后的字符串
      let textContent: string = fs.readTextSync(filePath, {
        // 确保指定正确的编码，默认为 'utf-8'
        encoding: 'utf-8'
      })
      console.log('The content of file', textContent)

      const numberArray: Array<number> = textContent
        .split(',')
        .map(s => parseFloat(s));

      // 2. 使用数字数组（Iterable<number>）创建 Float32Array
      const inputArray: Float32Array = new Float32Array(numberArray);
      console.log("=========DEMO_LOG: Input Data=====", inputArray)


      let output = await modelLoadPredict(modelBuffer.buffer.slice(0), [inputArray.buffer])
      //
      let out = new Float32Array(output[0].getData());

      console.log("=========DEMO_LOG: Output Data=====", out)

      if (this.currentMode === 0) {
        // 模式 0: 目标检测 (前4个模型对比)
        this.predictText = generateModelChoiceString(out);
      } else {
        // 模式 1: 图像增强 (9,10,11组排序)
        this.predictText = generateEnhanceRankString(out);
      }


    }
  }

  uiGetModeTitle(mode: number): string {
    if (mode === 0) return "图像模态单模型任务";
    if (mode === 1) return "图像模态多模型任务";
    return "文本模态任务";
  }

  // 【新增】辅助方法：获取副标题
  uiGetSubTitle(mode: number): string {
    if (mode === 0) return "人脸框检测模型选择";
    if (mode === 1) return "人像优化多模型任务选择";
    return "文本模态模型选择"; // mode 2 的自定义描述
  }

  build() {
    Column() {
      // ============================================================
      // 1. 顶部固定区域 (不会随内容滚动)
      //    包含：单选框、主标题、副标题、文件名
      // ============================================================
      Column() {
        // 1.1 模式选择单选框
        Row() {
          Text("选择模式：").fontSize(16).fontWeight(FontWeight.Bold)

          // 选项1：单模型
          Row() {
            Radio({ value: 'detection', group: 'modeGroup' })
              .checked(this.currentMode === 0)
              .onChange((isChecked) => { if (isChecked) this.switchMode(0); })
            Text('单模型').fontSize(14)
          }.margin({ right: 5 })

          // 选项2：多模型
          Row() {
            Radio({ value: 'enhance', group: 'modeGroup' })
              .checked(this.currentMode === 1)
              .onChange((isChecked) => { if (isChecked) this.switchMode(1); })
            Text('多模型').fontSize(14)
          }.margin({ right: 5 })

          // 选项3：文本推理
          Row() {
            Radio({ value: 'text_inference', group: 'modeGroup' })
              .checked(this.currentMode === 2)
              .onChange((isChecked) => { if (isChecked) this.switchMode(2); })
            Text('文本推理').fontSize(14)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding(10)

        // 1.2 主标题 (恢复显示)
        Text(this.uiGetModeTitle(this.currentMode))
          .width(CommonConstants.FULL_PERCENT)
          .font({
            size: $r('app.float.All_title_font_size'),
            weight: CommonConstants.FONT_WEIGHT_700
          })
          .margin({
            top: 0,
            left: $r('app.float.title_margin_left'),
            bottom: $r('app.float.title_margin_bottom')
          })

        // 1.3 副标题 (恢复显示)
        Text(this.uiGetSubTitle(this.currentMode))
          .width(CommonConstants.FULL_PERCENT)
          .font({
            size: $r('app.float.Sub_title_font_size'),
            weight: CommonConstants.FONT_WEIGHT_700
          })
          .margin({
            left: $r('app.float.title_margin_left'),
            bottom: $r('app.float.title_margin_bottom')
          })

        // 1.4 文件名 (恢复显示)
        if(this.fileNameShow){
          Text(this.fileName)
            .width($r('app.string.EntryAbility_label'))
            .font({
              size: $r('app.float.All_image_name_font_size'),
              weight: CommonConstants.FONT_WEIGHT_700
            })
            .margin({ left: 10, bottom: 5 })
        }
      }.width('100%')
       .backgroundColor(Color.White) // 防止背景透明导致文字重叠



      // ============================================================
      // 2. 中间弹性区域 (内容过多时内部滚动)
      //    使用 .layoutWeight(1) 占据剩余空间，防止挤压底部按钮
      // ============================================================
      Column() {
        Scroll() {
          Column() {
            // 2.1 内容展示 (文本 或 图片)
            if (this.currentMode === 2) {
              // === 文本模式展示 (固定高度) ===
              if (this.textShow) {
                Column() {
                  Text("原始文本内容:")
                    .fontSize(14)
                    .fontColor(Color.Gray)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .margin({ bottom: 5 })

                  // 【核心修改】
                  // 1. 给 Scroll 设置固定高度 (height(200))
                  // 2. 文本再长也只会在这个 200 的框里滚动
                  // 3. 这样结果就不会被顶飞了
                  Scroll() {
                    Text(this.textContent)
                      .fontSize(16)
                      .padding(10)
                      .lineHeight(24)
                      .width('100%') // 文本宽度撑满 Scroll
                  }
                  .height(200) // 【关键点】固定高度 200vp
                  .width('95%')
                  .backgroundColor('#F5F5F5')
                  .borderRadius(8)
                  .scrollBar(BarState.On) // 显示滚动条，提示用户可以滑动
                  .align(Alignment.TopStart)
                }
                .margin({ bottom: 20 })
                .width('100%')
                .alignItems(HorizontalAlign.Center)
              }
            }else {
              // === 图片模式展示 ===
              if (this.photoShow && this.uris.length > 0) {
                Image(this.uris[0])
                  .height(200) // 图片高度保持固定或百分比
                  .objectFit(ImageFit.Contain)
                  .borderRadius(10)
                  .margin({ bottom: 20 })
              }
            }

            // 2.2 推理结果展示 (接在内容下面)
            if (this.predictResultShow) {
              Text(this.predictText)
                .fontSize(16)
                .fontColor('#007DFF')
                .fontWeight(FontWeight.Medium)
                .margin(10)
            }
          }
          .width('100%')
        }
        .width('100%')
        .height('100%') // Scroll 填满这个弹性 Column
        .align(Alignment.TopStart)
      }
      .layoutWeight(1) // 【关键点】权重为1，霸占中间所有剩余空间
      .width('100%')
      .padding({ left: 10, right: 10 })


      // ============================================================
      // 3. 底部固定区域 (按钮)
      //    始终固定在屏幕底部
      // ============================================================
      Column() {
        Button('数据集批量测试')
          .width($r('app.float.button_width'))
          .height($r('app.float.button_height'))
          .margin({ top: 10 })
          .onClick(()=>{
            this.predictInput()
          })

        Button('单图测试（测试用）')
          .width($r('app.float.button_width'))
          .height($r('app.float.button_height'))
          .margin({
            top: $r('app.float.button_margin_top'),
            bottom: 20 // 底部留白
          })
          .onClick(() =>{
            this.testOneInput()
          })
      }
      .width('100%')
      .backgroundColor(Color.White) // 防止背景透明导致文字重叠
    }
    .width(CommonConstants.FULL_PERCENT)
    .height(CommonConstants.FULL_PERCENT)
  }
}