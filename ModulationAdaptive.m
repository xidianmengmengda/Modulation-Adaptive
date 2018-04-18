clear classes;clc;
format compact
%% Init
FrameCount = 200;
FramePerMER = 2; % ��֡��һ��MER(1 2 4 5 10 20)
SNRs = linspace(4,30,FrameCount+1); % ���������SNR����
SNRs = SNRs(1:FrameCount);
MERs = zeros(1,FrameCount/FramePerMER+1); % ��¼MER����ͼ��
Mods = zeros(1,FrameCount); % ��¼���ƽ���M����ͼ��
BERs = zeros(1,FrameCount); % ��¼BER����ͼ��
MER = SNRs(1);
ModAdpThres = [10 20]; %���ֵ��Ʒ�ʽ��MER����ֵ(dB)
% My Msg
MyMsgStrLength = 240; % ����ַ����ַ���
MyMsgLength = MyMsgStrLength*7;
MyCharSet = 'abcdefghijklmnopqrstuvwxyz0123456789';
MyMsgStr = MyCharSet(randi([1 36],1,MyMsgStrLength)); % ����ַ���
MyMsgBits = de2bi(int8(MyMsgStr),7,'left-msb')';
MyMsgBits = reshape(MyMsgBits,MyMsgStrLength*7,1); % �������

UpsamplingFactor = 4;
DownsamplingFactor = 2; 
PostFilterOversampling = UpsamplingFactor/DownsamplingFactor;
SampleRate = 2e5; 

FrameSize = 111; % һ֡���ܷ�����
BarkerLength = 13; % Barker�������

ScramblerBase = 2;
ScramblerPolynomial = [1 1 1 0 1];
ScramblerInitialConditions = [0 0 0 0];
RxBufferedFrames = 10;
RaisedCosineFilterSpan = 10;

CoarseCompFrequencyResolution = 25; 
K = 1;A = 1/sqrt(2);
PhaseRecoveryLoopBandwidth = 0.01;
PhaseRecoveryDampingFactor = 1;
TimingRecoveryLoopBandwidth = 0.01;
TimingRecoveryDampingFactor = 1;
TimingErrorDetectorGain = 2.7*2*K*A^2+2.7*2*K*A^2; 
BarkerCode = [+1; +1; +1; +1; +1; -1; -1; +1; +1; -1; +1; -1; +1];    
ModulatedHeader = sqrt(2)/2 * (-1-1i) * BarkerCode;
Rolloff = 0.5;
TransmitterFilterCoefficients = rcosdesign(Rolloff, ...
    RaisedCosineFilterSpan, UpsamplingFactor);
ReceiverFilterCoefficients = rcosdesign(Rolloff, ...
    RaisedCosineFilterSpan, UpsamplingFactor);
%% Flags
useScopes = true;
printOption = true;
%% Objects
% Tx
pScrambler = comm.Scrambler(ScramblerBase,ScramblerPolynomial, ...
    ScramblerInitialConditions); % �������
p4QAMModulator  = comm.RectangularQAMModulator(4,'BitInput',true, ...
    'NormalizationMethod', 'Average power');
p16QAMModulator  = comm.RectangularQAMModulator(16,'BitInput',true, ...
    'NormalizationMethod', 'Average power');
p64QAMModulator  = comm.RectangularQAMModulator(64,'BitInput',true, ...
    'NormalizationMethod','Average power');
pTransmitterFilter = dsp.FIRInterpolator(UpsamplingFactor, ...
    TransmitterFilterCoefficients); % �������+�ϲ����˲�������
% Channel
% Rx
p4QAMDemodulator = comm.RectangularQAMDemodulator(4,'BitOutput',true, ...
    'NormalizationMethod', 'Average power');
p16QAMDemodulator = comm.RectangularQAMDemodulator(16,'BitOutput',true, ...
    'NormalizationMethod', 'Average power');
p64QAMDemodulator = comm.RectangularQAMDemodulator(64,'BitOutput',true, ...
    'NormalizationMethod', 'Average power');
pAGC = comm.AGC;
pRxFilter = dsp.FIRDecimator( ...
    'Numerator', ReceiverFilterCoefficients, ...
    'DecimationFactor', DownsamplingFactor); % ƥ���˲�+�²����˲�������
pTimingRec = comm.SymbolSynchronizer( ...
    'TimingErrorDetector',     'Zero-Crossing (decision-directed)', ...
    'SamplesPerSymbol',        PostFilterOversampling, ...
    'DampingFactor',           TimingRecoveryDampingFactor, ...
    'NormalizedLoopBandwidth', TimingRecoveryLoopBandwidth, ...
    'DetectorGain',            TimingErrorDetectorGain);   % ����ͬ������
pFrameSync = FrameFormation( ...
    'OutputFrameLength',      FrameSize, ...
    'PerformSynchronization', true, ...
    'FrameHeader',            ModulatedHeader); % ֡ͬ������
pCorrelator = dsp.Crosscorrelator;
pDescrambler = comm.Descrambler(ScramblerBase,ScramblerPolynomial, ...
    ScramblerInitialConditions);
pErrorRateCalc = comm.ErrorRate;  % ����BER����
pMER = comm.MER; % ����MER����
% Scopes
pRxConstellation = comm.ConstellationDiagram( ...
        'ShowGrid', true, ...
        'Position', figposition([1.5 72 17 20]), ...                    
        'SamplesPerSymbol', 2, ...                    
        'YLimits', [-1.5 1.5], ...
        'XLimits', [-1.5 1.5], ...
        'Title', 'After Raised Cosine Rx Filter', ...
        'ReferenceConstellation',[]); % ����ͼ����
%% Run
% Msg
MyMsgCount = 0; % �ı�ָ�룬Ϊ��һ֡���ݷ��͵����һ���ַ�
msg = zeros(196,1);
for count = 1:FrameCount
    % Tx
    msg_pre = msg;
    % Modulation Adaptive
    if MER<ModAdpThres(1)
        M = 4; % ���ƽ���
        MessageLength = (FrameSize-BarkerLength)*2; % ��Ϣ������
        msgBin = [MyMsgBits;MyMsgBits]; % ѭ�������ı�
        msgBin = msgBin(MyMsgCount+1:MyMsgCount+MessageLength,1); 
        % ������һ֡��
        msg = double(msgBin);
        scrambledData = step(pScrambler, msg); % ����
        modulatedData = step(p4QAMModulator, scrambledData); %��Ϣ����
    elseif MER<ModAdpThres(2)
        M = 16;
        MessageLength = (FrameSize-BarkerLength)*4;
        msgBin = [MyMsgBits;MyMsgBits];
        msgBin = msgBin(MyMsgCount+1:MyMsgCount+MessageLength,1);
        msg = double(msgBin);
        scrambledData = step(pScrambler, msg);
        modulatedData = step(p16QAMModulator, scrambledData);
    else
        M = 64;
        MessageLength = (FrameSize-BarkerLength)*6;
        msgBin = [MyMsgBits;MyMsgBits];
        msgBin = msgBin(MyMsgCount+1:MyMsgCount+MessageLength,1);
        msg = double(msgBin);
        scrambledData = step(pScrambler, msg);
        modulatedData = step(p64QAMModulator, scrambledData);
    end
    MyMsgCount = mod(MyMsgCount+MessageLength,MyMsgStrLength*7);
    transmittedData = [ModulatedHeader; modulatedData]; % ��֡
    transmittedSignal=step(pTransmitterFilter,transmittedData);%�����˲�+�ϲ���
    % Channel
    pAWGNChannel = comm.AWGNChannel( ...
        'NoiseMethod','Signal to noise ratio (SNR)', ...
        'SNR', SNRs(count)); % �ŵ�
    corruptSignal = step(pAWGNChannel, transmittedSignal); % �����ŵ�
    % Rx
    AGCSignal=1/sqrt(UpsamplingFactor)*step(pAGC,corruptSignal);%�Զ���������
    RCRxSignal = step(pRxFilter, AGCSignal); % ƥ���˲�+�²���
    [timingRecSignal,~] = step(pTimingRec, RCRxSignal); % ����ͬ��
    [symFrame,isFrameValid] = step(pFrameSync, timingRecSignal); % ֡ͬ��
    if isFrameValid
        phaseEst = round(angle(mean(conj(ModulatedHeader) ...
            .* symFrame(1:BarkerLength)))*2/pi)/2*pi;
        phShiftedData = symFrame .* exp(-1i*phaseEst);
        HeaderSymbols = phShiftedData(1:13); % ͷ������
        if mod(count,FramePerMER) == 0
            MER = pMER(ModulatedHeader,HeaderSymbols); % ����MER
        end
        MsgSymbols = phShiftedData(13+1:13+MessageLength/log2(M)); % ��Ϣ����
        if M == 4
            demodOut = step(p4QAMDemodulator, MsgSymbols); % ���
        elseif M == 16
            demodOut = step(p16QAMDemodulator, MsgSymbols); 
        else % M == 64
            demodOut = step(p64QAMDemodulator, MsgSymbols);
        end
        deScrData = step(pDescrambler,demodOut);
        if printOption
            disp(bits2ASCII(msg_pre)); % ��ʾ������Ϣ
            disp(bits2ASCII(deScrData)); % ��ʾ������Ϣ
        end
        if size(msg_pre) == size(deScrData)
            BER = step(pErrorRateCalc, msg_pre, deScrData); % ����BER
        else 
            BER = [0.5 0 0];
        end
        Mods(count) = M;
        BERs(count) = BER(1);
        MERs(count) = MER;
    end
    if useScopes % ����һ֡���ݵ�����ͼ���������ο�������
        if M == 4
            pRxConstellation.ReferenceConstellation = ...
                [sqrt(1/2)*(1+1i)*[-1 1], ...
                reshape((repmat([-1 1],2,1)-1i* ...
                repmat([-1 1],2,1)')*sqrt(1/2),1,4)];
        elseif M == 16
            pRxConstellation.ReferenceConstellation = ...
                [sqrt(1/2)*(1+1i)*[-1 1], ...
                reshape((repmat([-3 -1 1 3],4,1)-1i* ...
                repmat([-3 -1 1 3],4,1)')*sqrt(1/10),1,16)];
        else % M == 64
            pRxConstellation.ReferenceConstellation = ...
                [sqrt(1/2)*(1+1i)*[-1 1], ...
                reshape((repmat ([-7 -5 -3 -1 1 3 5 7],8,1)-1i* ...
                repmat([-7 -5 -3 -1 1 3 5 7],8,1)')*sqrt(1/42),1,64)];
        end
        step(pRxConstellation,RCRxSignal);
    end
    figure(1)
    subplot 211 % ���Ͷ�RCR�˲�����ķ����ź�
    plot([real(transmittedSignal),imag(transmittedSignal)]);
    title('Tx signal after RCR Filter')
    subplot 212 % ���ն˾��ŵ���Ľ����ź�
    plot([real(corruptSignal),imag(corruptSignal)]);
    title('Rx signal after Channel')
end
%% Plot
figure(2)
subplot 311 % SNR & MER vs. FrameCount
plot(SNRs);
hold on
plot(MERs);
axis([0,FrameCount,0,50])
legend('SNR','MER')
title('SNR & MER')

subplot 312 % ���ƽ�����2/4/6�� vs. FrameCount
plot(log2(Mods));
axis([0,FrameCount,0,8])
title('Bits Per Symbol Log_2(M)')

subplot 313 % BER vs. FrameCount
plot(BERs);
axis([0,FrameCount,0,0.55])
title('BER')