import { modelLoad, modelPredict } from '../model/Model';
import Logger from '../common/utils/Logger'
import { resourceManager } from '@kit.LocalizationKit'
import { CommonConstants } from '../common/constants/CommonConstants';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, ListFileOptions } from '@kit.CoreFileKit';

async function preprocess(uri: string): Promise<ArrayBuffer[]> {
  // TODO: Replace the code below : retrieve model input ArrayBuffer[] using the filename
  console.log("Time Logger: start Preprocess %s", uri)
  let float32Array = new Float32Array(1 * 1 * 3);
  return [float32Array.buffer]
}

@Entry
@Component
struct Index {
  @State fileName: string = '';
  @State resultArray: Array<number> = [];
  @State isPredicting: boolean = false; // 增加一个状态防止重复点击

  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async predictTest(): Promise<void> {
    if (this.isPredicting) return;
    this.isPredicting = true;

    this.fileName = '正在初始化模型...';
    this.resultArray = [];

    try {
      // TODO: Change your file dir and file suffix
      let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      let filesDir = context.filesDir;
      let datasetDir = filesDir + '/your_file_dir'

      if (!fs.accessSync(datasetDir)) {
        this.fileName = '错误: 文件夹不存在 ' + datasetDir;
        this.isPredicting = false;
        return;
      }

      let listFileOption: ListFileOptions = {
        recursion: false,
        listNum: 0,
        filter: {
          suffix: [".png", ".jpg", ".jpeg"],
          fileSizeOver: 4096
        }
      };
      let filenames = fs.listFileSync(datasetDir, listFileOption);

      // TODO: Change your Model Config(modelName, deviceType...)
      let modelName = CommonConstants.MODEL_NAME
      let deviceType: 'cpu' | 'npu' = 'cpu'
      let resMgr: resourceManager.ResourceManager = this.context.getApplicationContext().resourceManager;
      let modelBuffer = await resMgr.getRawFileContent(modelName)
      let model = await modelLoad(modelBuffer.buffer.slice(0), deviceType)

      for (let i = 0; i < filenames.length; i++) {
        // 更新当前正在处理的文件名
        this.fileName = filenames[i];

        // 每次循环先清空结果，避免UI闪烁旧数据
        this.resultArray = [];

        console.log("Time Logger: start Predict %s", filenames[i])
        let input = await preprocess(datasetDir + '/' + filenames[i])
        let output = await modelPredict(model, input)
        console.log("Time Logger: start PostProcess %s", filenames[i])

        let outArray = new Float32Array(output[0].getData());

        // 临时数组用于收集数据，最后一次性赋值给State以触发UI刷新
        let tempResult: number[] = [];
        let printStr = '';
        for (let j = 0; j < outArray.length; j++) {
          printStr += outArray[j].toString() + ',';
          tempResult.push(Math.round(outArray[j] * CommonConstants.TEN_THOUSAND));
        }

        // 更新UI显示结果
        this.resultArray = tempResult;
        Logger.info(filenames[i] + ',MS_LITE_LOG PREDICT RESULT: ' + printStr);
      }
      this.fileName = `测试完成，共处理 ${filenames.length} 张图片`;
    } catch (e) {
      Logger.error('Predict Error: ' + JSON.stringify(e));
      this.fileName = '发生错误，请查看日志';
    } finally {
      this.isPredicting = false;
    }
  }

  build() {
    Column() {
      // 标题区域
      Text($r('app.string.EntryAbility_label'))
        .fontSize($r('app.float.All_title_font_size'))
        .fontWeight(CommonConstants.FONT_WEIGHT_700)
        .margin({ bottom: 20, top: 20 })

      // 控制按钮
      Button(this.isPredicting ? '正在运行...' : '开始推理测试')
        .width($r('app.float.button_width'))
        .height($r('app.float.button_height'))
        .enabled(!this.isPredicting) // 运行时禁用按钮
        .onClick(() => {
          this.predictTest()
        })
        .margin({ bottom: 20 })

      Divider().color($r('app.color.five_black')).strokeWidth(1).margin({ bottom: 10 })

      // 结果显示区域：如果文件名不为空才显示
      if (this.fileName) {
        Column() {
          // 1. 显示当前文件名
          Text('当前文件:')
            .fontSize(14)
            .fontColor(Color.Gray)
          Text(this.fileName)
            .fontSize($r('app.float.All_image_name_font_size'))
            .fontWeight(CommonConstants.FONT_WEIGHT_700)
            .margin({ bottom: 15, top: 5 })
            .textAlign(TextAlign.Center)

          // 2. 显示推理结果列表
          if (this.resultArray.length > 0) {
            List() {
              ForEach(this.resultArray, (item: number, index: number) => {
                ListItem() {
                  Row() {
                    Text(index + ': ')
                      .fontSize($r('app.float.common_font_size'))
                      .fontWeight(CommonConstants.FONT_WEIGHT_500)

                    Text(item.toString() + '%')
                      .fontSize($r('app.float.common_font_size'))
                      .fontWeight(CommonConstants.FONT_WEIGHT_500)
                      .textAlign(TextAlign.End)
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceBetween)
                  .padding({ left: 10, right: 10 })
                }
                .height($r('app.float.list_item_height'))
              }, (item: number, index: number) => index + '_' + item)
            }
            .width($r('app.float.list_width'))
            .height('50%') // 限制列表高度
            .backgroundColor($r("app.color.list_background"))
            .borderRadius($r('sys.float.corner_radius_level8'))
            .divider({
              strokeWidth: $r('app.float.stroke_width'),
              color: $r('app.color.five_black')
            })
          }
        }
        .width('100%')
        .layoutWeight(1) // 占满剩余空间
      } else {
        // 占位符
        Column() {
          Text("点击按钮开始测试")
            .fontColor(Color.Gray)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(20)
  }
}